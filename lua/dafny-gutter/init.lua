local M = {}

local namespace = vim.api.nvim_create_namespace("dafny_verification_gutter")
local animation_timer
local animation_phase = 0
local animation_elapsed = 0
local animated_buffers = {}

local tau = 2 * math.pi
local fallback_colors = {
	verified = 0x4ade80,
	error = 0xf87171,
	pending = 0xfacc15,
	skipped = 0x94a3b8,
}
local highlight_suffixes = {
	verified = "Verified",
	error = "Error",
	pending = "Pending",
	skipped = "Skipped",
}

local defaults = {
	enabled = true,
	symbols = {
		verified = "●",
		error = "●",
		pending = "~",
		skipped = "?",
		connector = "┃",
	},
	animation = {
		enabled = true,
		interval = 90,
		wavelength = 12,
		amplitude = 0.8,
		blink_interval = 450,
	},
}

local options = vim.deepcopy(defaults)

local function status_kind(status)
	if type(status) ~= "number" then
		return nil
	end
	if status == 1 or status == 2 then
		return "pending"
	end
	if status == 200 or status == 201 or status == 202 then
		return "verified"
	end
	if status == 250 then
		return "skipped"
	end
	if status == 350 or status == 351 or status == 352 then
		return "verified"
	end
	if status == 300 or status == 301 or status == 302 or status >= 400 then
		return "error"
	end
	return nil
end

local function is_explicit_failure(status)
	return status == 400 or status == 401 or status == 402 or status == 500
end

local function styles()
	return {
		verified = { symbol = options.symbols.verified, highlight = "DafnyGutterVerified" },
		error = { symbol = options.symbols.error, highlight = "DafnyGutterError" },
		pending = { symbol = options.symbols.pending, highlight = "DafnyGutterPending" },
		skipped = { symbol = options.symbols.skipped, highlight = "DafnyGutterSkipped" },
	}
end

local function wave_steps()
	return math.max(2, math.floor(tonumber(options.animation.wavelength) or defaults.animation.wavelength))
end

local function connector_highlight(kind, line)
	if not options.animation.enabled then
		return styles()[kind].highlight
	end
	return ("DafnyGutterConnector%s%02d"):format(highlight_suffixes[kind], (line - 1) % wave_steps())
end

local function marker_highlight(kind, fallback)
	if options.animation.enabled and kind == "error" then
		return "DafnyGutterErrorBlink"
	end
	return fallback
end

local function blend(color, target, amount)
	local red = math.floor(color / 0x10000) % 0x100
	local green = math.floor(color / 0x100) % 0x100
	local blue = color % 0x100
	local target_red = math.floor(target / 0x10000) % 0x100
	local target_green = math.floor(target / 0x100) % 0x100
	local target_blue = target % 0x100

	red = math.floor(red + (target_red - red) * amount + 0.5)
	green = math.floor(green + (target_green - green) * amount + 0.5)
	blue = math.floor(blue + (target_blue - blue) * amount + 0.5)
	return red * 0x10000 + green * 0x100 + blue
end

local function resolved_foreground(group, fallback)
	local ok, highlight = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
	return ok and highlight.fg or fallback
end

local function update_connector_highlights()
	if not options.animation.enabled then
		return
	end

	local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
	local background = normal.bg or 0x000000
	local red = math.floor(background / 0x10000) % 0x100
	local green = math.floor(background / 0x100) % 0x100
	local blue = background % 0x100
	local target = (0.299 * red + 0.587 * green + 0.114 * blue) < 128 and 0xffffff or 0x000000
	local amplitude = math.max(0, math.min(1, tonumber(options.animation.amplitude) or defaults.animation.amplitude))
	local steps = wave_steps()
	local blink_interval = math.max(
		16,
		math.floor(tonumber(options.animation.blink_interval) or defaults.animation.blink_interval)
	)

	for kind, style in pairs(styles()) do
		local base = resolved_foreground(style.highlight, fallback_colors[kind])
		if kind == "error" then
			local light_red = blend(base, 0xffffff, amplitude * 0.55)
			local dark_red = blend(base, 0x000000, amplitude * 0.45)
			local color = math.floor(animation_elapsed / blink_interval) % 2 == 0 and light_red or dark_red
			vim.api.nvim_set_hl(0, "DafnyGutterErrorBlink", { fg = color })
			for slot = 0, steps - 1 do
				local group = ("DafnyGutterConnector%s%02d"):format(highlight_suffixes[kind], slot)
				vim.api.nvim_set_hl(0, group, { fg = color })
			end
		else
			for slot = 0, steps - 1 do
				local wave = math.sin(tau * (slot - animation_phase) / steps)
				local group = ("DafnyGutterConnector%s%02d"):format(highlight_suffixes[kind], slot)
				local color = wave >= 0 and blend(base, target, amplitude * wave)
					or blend(base, background, amplitude * 0.35 * -wave)
				vim.api.nvim_set_hl(0, group, { fg = color })
			end
		end
	end
end

local function stop_animation()
	if animation_timer then
		animation_timer:stop()
		animation_timer:close()
		animation_timer = nil
	end
end

local function sync_animation()
	if not options.enabled or not options.animation.enabled or not next(animated_buffers) then
		stop_animation()
		return
	end
	if animation_timer then
		return
	end

	local interval = math.max(16, math.floor(tonumber(options.animation.interval) or defaults.animation.interval))
	animation_elapsed = 0
	update_connector_highlights()
	animation_timer = (vim.uv or vim.loop).new_timer()
	animation_timer:start(interval, interval, vim.schedule_wrap(function()
		if not options.enabled or not next(animated_buffers) then
			stop_animation()
			return
		end
		animation_phase = (animation_phase + 1) % wave_steps()
		animation_elapsed = animation_elapsed + interval
		update_connector_highlights()
		pcall(vim.cmd, "redraw")
	end))
end

local function render(result)
	if not options.enabled or not result or not result.uri or type(result.perLineStatus) ~= "table" then
		return
	end

	local bufnr = vim.uri_to_bufnr(result.uri)
	if not vim.api.nvim_buf_is_loaded(bufnr) then
		return
	end

	vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)

	local line_statuses = result.perLineStatus
	local has_later_status = {}
	local found_status = false
	for index = #line_statuses, 1, -1 do
		has_later_status[index] = found_status
		if status_kind(line_statuses[index]) then
			found_status = true
		end
	end

	local previous_kind
	local connector_count = 0
	local has_blinking_error = false
	local max_line = vim.api.nvim_buf_line_count(bufnr)
	for index, status in ipairs(line_statuses) do
		if index > max_line then
			break
		end

		local kind = status_kind(status)
		local style = kind and styles()[kind] or nil
		local symbol
		local is_connector = false

		if style then
			if kind ~= previous_kind or is_explicit_failure(status) then
				symbol = style.symbol
			else
				symbol = options.symbols.connector
				is_connector = true
			end
			previous_kind = kind
		elseif previous_kind and has_later_status[index] then
			style = styles()[previous_kind]
			symbol = options.symbols.connector
			is_connector = true
		else
			previous_kind = nil
		end

		if style and symbol then
			if previous_kind == "error" then
				has_blinking_error = true
			end
			if is_connector then
				connector_count = connector_count + 1
			end
			vim.api.nvim_buf_set_extmark(bufnr, namespace, index - 1, 0, {
				sign_text = symbol,
				sign_hl_group = is_connector and connector_highlight(previous_kind, index)
					or marker_highlight(kind, style.highlight),
				priority = 20,
			})
		end
	end

	animated_buffers[bufnr] = (connector_count > 0 or has_blinking_error) and true or nil
	sync_animation()
end

function M.clear(bufnr)
	bufnr = bufnr or 0
	local resolved_bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
	vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
	animated_buffers[resolved_bufnr] = nil
	sync_animation()
end

function M.enable()
	options.enabled = true
end

function M.disable()
	options.enabled = false
	stop_animation()
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		M.clear(bufnr)
	end
end

local function setup_highlights()
	vim.api.nvim_set_hl(0, "DafnyGutterVerified", { default = true, link = "DiagnosticOk" })
	vim.api.nvim_set_hl(0, "DafnyGutterError", { default = true, link = "DiagnosticError" })
	vim.api.nvim_set_hl(0, "DafnyGutterPending", { default = true, link = "DiagnosticWarn" })
	vim.api.nvim_set_hl(0, "DafnyGutterSkipped", { default = true, link = "Comment" })
	update_connector_highlights()
end

function M.setup(user_options)
	options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), user_options or {})

	setup_highlights()

	vim.lsp.handlers["dafny/verification/status/gutter"] = function(err, result)
		if err then
			vim.notify("Dafny gutter status error: " .. tostring(err.message or err), vim.log.levels.WARN)
			return
		end
		render(result)
	end

	local group = vim.api.nvim_create_augroup("DafnyGutter", { clear = true })
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		callback = setup_highlights,
	})
	vim.api.nvim_create_autocmd("LspDetach", {
		group = group,
		callback = function(event)
			local client = vim.lsp.get_client_by_id(event.data.client_id)
			if client and client.name == "dafny" then
				M.clear(event.buf)
			end
		end,
	})
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = group,
		callback = function(event)
			animated_buffers[event.buf] = nil
			sync_animation()
		end,
	})
end

return M
