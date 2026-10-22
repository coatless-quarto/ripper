-- ============================================================================
-- TYPES
-- ============================================================================

---@alias RipperLinksPosition "top"|"bottom"|"custom"|"none"

---@class RipperConfig
---@field include_yaml boolean `include-yaml`: add document metadata as comments at the top of each script
---@field script_links_position RipperLinksPosition `script-links-position`: where the links section goes
---@field output_name string|nil `output-name`: base name for the scripts (default: the document's name)
---@field output_dir string|nil `output-dir`: directory for the scripts (default: the document's directory)
---@field debug boolean `debug`: log each step to the console

---@class LangSpec
---@field ext string File extension, including the dot
---@field comment string Comment prefix for the metadata header

-- ============================================================================
-- STATE VARIABLES & CONFIGURATION
-- ============================================================================

--- Configuration from `extensions.ripper`, filled in by `read_config`.
---@type RipperConfig
local config = {
  include_yaml = true,
  script_links_position = "bottom",
  output_name = nil,
  output_dir = nil,
  debug = false,
}

--- Values accepted by `script-links-position`.
---@type table<string, boolean>
local valid_positions = { top = true, bottom = true, custom = true, none = true }

--- File extension and metadata comment prefix for each supported language.
---@type table<string, LangSpec>
local lang_specs = {
  r          = { ext = ".R",     comment = "#'" },
  python     = { ext = ".py",    comment = "#'" },
  julia      = { ext = ".jl",    comment = "#'" },
  bash       = { ext = ".sh",    comment = "#'" },
  javascript = { ext = ".js",    comment = "//'" },
  typescript = { ext = ".ts",    comment = "//'" },
  sql        = { ext = ".sql",   comment = "--'" },
  rust       = { ext = ".rs",    comment = "//'" },
  go         = { ext = ".go",    comment = "//'" },
  cpp        = { ext = ".cpp",   comment = "//'" },
  c          = { ext = ".c",     comment = "//'" },
  java       = { ext = ".java",  comment = "//'" },
  scala      = { ext = ".scala", comment = "//'" },
  ruby       = { ext = ".rb",    comment = "#'" },
  perl       = { ext = ".pl",    comment = "#'" },
  php        = { ext = ".php",   comment = "//'" },
}

--- Code block text collected for each language.
---@type table<string, string[]>
local code_blocks = {}

--- Languages in the order they first appear in the document.
---@type string[]
local languages = {}

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

--- Log a debug message if debug mode is enabled.
--- Prefixes messages with "[ripper]" for easy identification.
---@param message string The message to log
local function debug_log(message)
  if config.debug then
    quarto.log.output("[ripper] " .. message)
  end
end

--- Read a boolean option; any value other than `false` counts as true.
---@param opts table Options table from metadata
---@param key string
---@param default boolean Value to use when the option is absent
---@return boolean
local function read_bool(opts, key, default)
  local value = opts[key]
  if value == nil then
    return default
  end
  return value ~= false
end

--- Read an option as a string.
---@param opts table Options table from metadata
---@param key string
---@return string|nil value The stringified option, or nil if it is absent
local function read_string(opts, key)
  local value = opts[key]
  if not value then
    return nil
  end
  return pandoc.utils.stringify(value)
end

--- Read configuration from `extensions.ripper` in the document metadata.
---@param meta pandoc.Meta The document metadata
local function read_config(meta)
  local extensions = meta.extensions
  local opts = type(extensions) == "table" and extensions.ripper or nil
  if type(opts) == "table" then
    config.include_yaml = read_bool(opts, "include-yaml", config.include_yaml)
    config.debug = read_bool(opts, "debug", config.debug)
    config.output_name = read_string(opts, "output-name")

    local position = read_string(opts, "script-links-position")
    if position then
      local normalized = position:lower()
      if valid_positions[normalized] then
        config.script_links_position = normalized --[[@as RipperLinksPosition]]
      else
        quarto.log.warning("Invalid script-links-position '" .. position ..
          "'. Expected one of: top, bottom, custom, none. Using 'bottom'.")
      end
    end

    local output_dir = read_string(opts, "output-dir")
    if output_dir ~= "" then
      config.output_dir = output_dir
    end
  end

  debug_log("Configuration loaded: include_yaml=" .. tostring(config.include_yaml) ..
            ", script_links_position=" .. config.script_links_position ..
            ", output_name=" .. tostring(config.output_name or "auto") ..
            ", output_dir=" .. tostring(config.output_dir or "same as document") ..
            ", debug=" .. tostring(config.debug))
end

-- ============================================================================
-- YAML HEADER FUNCTIONS
-- ============================================================================

--- Extract a metadata field as a string.
--- List values (e.g., several authors) are joined with ", ".
---@param meta pandoc.Meta The document metadata
---@param field_name string The name of the field to extract
---@return string|nil value The field value as a string, or nil if not present
local function get_meta_field(meta, field_name)
  local value = meta[field_name]
  if not value then
    return nil
  end
  if pandoc.utils.type(value) == "List" then
    ---@cast value pandoc.List
    local items = {}
    for _, item in ipairs(value) do
      table.insert(items, pandoc.utils.stringify(item))
    end
    return table.concat(items, ", ")
  end
  return pandoc.utils.stringify(value)
end

--- Convert document metadata to commented lines for a script file.
--- Includes the common fields title, author, date, and format, when present.
---@param meta pandoc.Meta The document metadata
---@param lang string The programming language identifier
---@return string header The commented header, ending in a newline
local function format_yaml_header(meta, lang)
  debug_log("Building YAML header for " .. lang)

  local comment = lang_specs[lang].comment
  local lines = {comment .. " ---"}

  for _, field_name in ipairs({"title", "author", "date", "format"}) do
    local value = get_meta_field(meta, field_name)
    if value then
      table.insert(lines, comment .. " " .. field_name .. ": " .. value)
    end
  end

  table.insert(lines, comment .. " ---")
  table.insert(lines, comment .. " ")

  return table.concat(lines, "\n") .. "\n"
end

-- ============================================================================
-- SECTION CREATION FUNCTIONS
-- ============================================================================

--- Create a section with links to generated script files.
--- For RevealJS, the header is level 2 with the 'scrollable' class; otherwise
--- it is level 1. Header text is singular for 1 file, plural for multiple files.
---@param paths string[] Paths of the generated scripts, used as link text and href
---@return pandoc.Block[] blocks Header, description, and bullet list of links
local function create_script_links_section(paths)
  debug_log("Creating script links section with " .. #paths .. " file(s)")

  local is_revealjs = quarto.doc.is_format("revealjs")
  local header_level = is_revealjs and 2 or 1
  local header_classes = is_revealjs and {"scrollable"} or {}
  local header_text = #paths == 1 and "Script file" or "Script files"

  local list_items = {}
  for _, path in ipairs(paths) do
    table.insert(list_items, {pandoc.Plain({pandoc.Link({pandoc.Str(path)}, path)})})
  end

  return {
    pandoc.Header(header_level, {pandoc.Str(header_text)}, pandoc.Attr("", header_classes)),
    pandoc.Para({pandoc.Str("The code for this document can be found here:")}),
    pandoc.BulletList(list_items),
  }
end

-- ============================================================================
-- FILE WRITING FUNCTIONS
-- ============================================================================

--- Build complete file content for a programming language.
--- Combines the YAML header (if enabled) with all code blocks for the language.
---@param lang string The programming language identifier
---@param blocks string[] Code block text, in document order
---@param meta pandoc.Meta The document metadata
---@return string content Complete file content ready to write
local function build_file_content(lang, blocks, meta)
  debug_log("Building content for " .. lang .. " with " .. #blocks .. " code block(s)")

  local content = {}

  if config.include_yaml then
    table.insert(content, format_yaml_header(meta, lang))
  else
    debug_log("Skipping YAML header for " .. lang .. " (include_yaml=false)")
  end

  for i, code in ipairs(blocks) do
    if i > 1 then
      table.insert(content, "\n")  -- Separator between blocks
    end
    table.insert(content, code)
  end

  return table.concat(content, "\n") .. "\n"
end

--- Write a script file to disk.
---@param filename string The full path/name of file to create
---@param content string The file content to write
---@return boolean ok Whether the file was written
local function write_script_file(filename, content)
  debug_log("Writing file: " .. filename .. " (" .. #content .. " bytes)")

  local file = io.open(filename, "w")
  if not file then
    debug_log("ERROR: Failed to create file: " .. filename)
    quarto.log.error("Failed to create file: " .. filename)
    return false
  end
  file:write(content)
  file:close()
  debug_log("Successfully wrote " .. filename)
  return true
end

--- Write one script per collected language.
---@param base_name string The base filename (without extension)
---@param meta pandoc.Meta The document metadata
---@return string[] paths Paths of the scripts that were written
local function write_all_scripts(base_name, meta)
  debug_log("Writing all scripts with base name: " .. base_name)
  debug_log("Found code blocks in " .. #languages .. " language(s)")

  -- Determine output directory and ensure it exists
  local output_path_prefix = ""
  local output_dir = config.output_dir
  if output_dir then
    -- Normalize to avoid trailing slashes (e.g., "scripts/" -> "scripts")
    local normalized_output_dir = output_dir:gsub("/+$", "")
    debug_log("Using output directory: " .. normalized_output_dir)
    debug_log("Ensuring directory exists: " .. normalized_output_dir)
    -- Throws if the directory can't be created
    pandoc.system.make_directory(normalized_output_dir, true)
    output_path_prefix = normalized_output_dir .. "/"
  end

  local paths = {}
  for _, lang in ipairs(languages) do
    local full_path = output_path_prefix .. base_name .. lang_specs[lang].ext
    local content = build_file_content(lang, code_blocks[lang], meta)
    if write_script_file(full_path, content) then
      table.insert(paths, full_path)
    end
  end

  debug_log("Successfully created " .. #paths .. " file(s)")

  return paths
end

-- ============================================================================
-- BLOCK INSERTION FUNCTIONS
-- ============================================================================

--- Insert blocks at the top of the document.
---@param doc pandoc.Pandoc The document object
---@param blocks pandoc.Block[] Blocks to insert
local function insert_at_top(doc, blocks)
  debug_log("Inserting " .. #blocks .. " block(s) at top of document")
  for i, block in ipairs(blocks) do
    doc.blocks:insert(i, block)
  end
end

--- Insert blocks at the bottom of the document.
---@param doc pandoc.Pandoc The document object
---@param blocks pandoc.Block[] Blocks to insert
local function insert_at_bottom(doc, blocks)
  debug_log("Inserting " .. #blocks .. " block(s) at bottom of document")
  for _, block in ipairs(blocks) do
    doc.blocks:insert(block)
  end
end

--- Replace the top-level marker div with the blocks.
--- Falls back to top insertion if the div is not found.
---@param doc pandoc.Pandoc The document object
---@param blocks pandoc.Block[] Blocks to insert
---@param div_id string The ID of the marker div to replace
local function insert_at_custom(doc, blocks, div_id)
  debug_log("Searching for custom position div: #" .. div_id)

  for i, block in ipairs(doc.blocks) do
    if block.t == "Div" and block.identifier == div_id then
      debug_log("Found custom position div at block " .. i .. ", inserting " .. #blocks .. " block(s)")
      doc.blocks:remove(i)
      for j, section_block in ipairs(blocks) do
        doc.blocks:insert(i + j - 1, section_block)
      end
      return
    end
  end

  quarto.log.warning("No div with id '" .. div_id .. "' found. Inserting at top.")
  debug_log("Custom position div not found, falling back to top insertion")
  insert_at_top(doc, blocks)
end

-- ============================================================================
-- FILTER FUNCTIONS
-- ============================================================================

--- First pass: read the configuration.
---@param meta pandoc.Meta The document metadata
local function process_meta(meta)
  read_config(meta)
end

--- Second pass: collect the text of each code block in a supported language.
---@param block pandoc.CodeBlock The code block to process
local function process_code_block(block)
  -- classes[1] is typically the language
  local lang = block.classes[1]

  if lang and lang_specs[lang] then
    if not code_blocks[lang] then
      code_blocks[lang] = {}
      table.insert(languages, lang)
      debug_log("Initialized storage for language: " .. lang)
    end
    table.insert(code_blocks[lang], block.text)
    debug_log("Collected code block for language: " .. lang .. " (" .. #block.text .. " bytes)")
  elseif lang then
    debug_log("Skipping unsupported language: " .. lang)
  end
end

--- Third pass: write the script files and insert the links section.
---@param doc pandoc.Pandoc The complete document
---@return pandoc.Pandoc doc The document with the script links section
local function process_document(doc)
  debug_log("=== Starting document processing ===")

  local output_name = config.output_name or
    pandoc.path.split_extension(PANDOC_STATE.output_file or "output")
  debug_log("Output base name: " .. output_name)

  local paths = write_all_scripts(output_name, doc.meta)

  local position = config.script_links_position
  if position ~= "none" and #paths > 0 then
    local section_blocks = create_script_links_section(paths)
    debug_log("Insert position: " .. position)
    if position == "top" then
      insert_at_top(doc, section_blocks)
    elseif position == "bottom" then
      insert_at_bottom(doc, section_blocks)
    else
      insert_at_custom(doc, section_blocks, "ripper-links")
    end
  end

  debug_log("=== Document processing complete ===")

  return doc
end

-- ============================================================================
-- FILTER REGISTRATION
-- ============================================================================

return {
  { Meta = process_meta },
  { CodeBlock = process_code_block },
  { Pandoc = process_document }
}
