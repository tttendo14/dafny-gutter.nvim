local M = {}

local namespace = vim.api.nvim_create_namespace("dafny_verification_gutter")

local defaults = {
	enabled = true,
	symbols = {
		verified = "✓",
		error = "✗",
		pending = "…",
		skipped = "?",
		connector = "｜",
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
	local max_line = vim.api.nvim_buf_line_count(bufnr)
	for index, status in ipairs(line_statuses) do
		if index > max_line then
			break
		end

		local kind = status_kind(status)
		local style = kind and styles()[kind] or nil
		local symbol

		if style then
			symbol = (kind ~= previous_kind or is_explicit_failure(status)) and style.symbol
				or options.symbols.connector
			previous_kind = kind
		elseif previous_kind and has_later_status[index] then
			style = styles()[previous_kind]
			symbol = options.symbols.connector
		else
			previous_kind = nil
		end

		if style and symbol then
			vim.api.nvim_buf_set_extmark(bufnr, namespace, index - 1, 0, {
				sign_text = symbol,
				sign_hl_group = style.highlight,
				priority = 20,
			})
		end
	end
end

function M.clear(bufnr)
	vim.api.nvim_buf_clear_namespace(bufnr or 0, namespace, 0, -1)
end

function M.enable()
	options.enabled = true
end

function M.disable()
	options.enabled = false
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		M.clear(bufnr)
	end
end

function M.setup(user_options)
	options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), user_options or {})

	vim.api.nvim_set_hl(0, "DafnyGutterVerified", { default = true, link = "DiagnosticOk" })
	vim.api.nvim_set_hl(0, "DafnyGutterError", { default = true, link = "DiagnosticError" })
	vim.api.nvim_set_hl(0, "DafnyGutterPending", { default = true, link = "DiagnosticWarn" })
	vim.api.nvim_set_hl(0, "DafnyGutterSkipped", { default = true, link = "Comment" })

	vim.lsp.handlers["dafny/verification/status/gutter"] = function(err, result)
		if err then
			vim.notify("Dafny gutter status error: " .. tostring(err.message or err), vim.log.levels.WARN)
			return
		end
		render(result)
	end

	local group = vim.api.nvim_create_augroup("DafnyGutter", { clear = true })
	vim.api.nvim_create_autocmd("LspDetach", {
		group = group,
		callback = function(event)
			local client = vim.lsp.get_client_by_id(event.data.client_id)
			if client and client.name == "dafny" then
				M.clear(event.buf)
			end
		end,
	})
end

return M
