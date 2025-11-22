-- ============================================================================
-- STATE VARIABLES & CONFIGURATION
-- ============================================================================

--- Storage for code blocks organized by programming language.
-- @table code_blocks
local code_blocks = {}

--- YAML metadata from the document.
-- @field yaml_meta
local yaml_meta = nil

--- Flag to control inclusion of YAML header in script files.
-- @field include_yaml
local include_yaml = true

--- Base name for output files.
-- @field output_name
local output_name = nil

--- Position where script links section should appear.
-- Valid values: "top", "bottom", "custom", "none"
-- @field script_links_position
local script_links_position = "bottom"

--- Custom base name for output files (overrides document name).
-- @field custom_base_name
local custom_base_name = nil  -- optional custom output name

--- Debug mode flag for verbose logging.
-- @field debug
local debug = false

--- Language to file extension mapping.
-- Maps language names to their corresponding file extensions.
-- @table lang_extensions
local lang_extensions = {
  r = ".R",
  python = ".py",
  julia = ".jl",
  bash = ".sh",
  javascript = ".js",
  typescript = ".ts",
  sql = ".sql",
  rust = ".rs",
  go = ".go",
  cpp = ".cpp",
  c = ".c",
  java = ".java",
  scala = ".scala",
  ruby = ".rb",
  perl = ".pl",
  php = ".php"
}

--- Comment style mapping for different languages.
-- Maps language names to their comment prefix style for metadata.
-- @table comment_styles
local comment_styles = {
  r = "#'",
  python = "#'",
  julia = "#'",
  bash = "#'",
  sql = "--'",
  javascript = "//'",
  typescript = "//'",
  rust = "//'",
  go = "//'",
  cpp = "//'",
  c = "//'",
  java = "//'",
  scala = "//'",
  ruby = "#'",
  perl = "#'",
  php = "//'",
}

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

--- Get the comment prefix for a programming language.
-- Returns the appropriate comment style for adding metadata to script files.
-- @param lang string The programming language identifier
-- @return string The comment prefix (e.g., "#'" for R, "//'" for JavaScript)
local function get_comment_prefix(lang)
  return comment_styles[lang] or "#'"
end

--- Extract a metadata field as a string.
-- Safely extracts and stringifies a metadata field from the document's YAML.
-- @param meta table The metadata table
-- @param field_name string The name of the field to extract
-- @return string|nil The field value as a string, or nil if not present
local function get_meta_field(meta, field_name)
  if meta[field_name] then
    return pandoc.utils.stringify(meta[field_name])
  end
  return nil
end

--- Log a debug message if debug mode is enabled.
-- Prefixes messages with "[ripper]" for easy identification.
-- @param message string The message to log
local function debug_log(message)
  if debug then
    quarto.log.output("[ripper] " .. message)
  end
end

-- ============================================================================
-- YAML HEADER FUNCTIONS
-- ============================================================================

--- Add a commented metadata line to the header.
-- Appends a formatted metadata line to the lines array if value is present.
-- @param lines table Array of strings to append to
-- @param comment string The comment prefix for the language
-- @param field_name string The metadata field name
-- @param value string|nil The metadata value (skipped if nil)
local function add_meta_line(lines, comment, field_name, value)
  if value then
    table.insert(lines, comment .. " " .. field_name .. ": " .. value)
  end
end

--- Convert YAML metadata to commented lines for script files.
-- Formats document metadata as comments in the target language's style.
-- Includes common fields: title, author, date, format.
-- @param meta table The document metadata
-- @param lang string The programming language identifier
-- @return string Formatted YAML header as comments, or empty string if disabled
local function format_yaml_header(meta, lang)
  if not include_yaml then
    debug_log("Skipping YAML header for " .. lang .. " (include_yaml=false)")
    return ""
  end
  
  debug_log("Building YAML header for " .. lang)
  
  local comment = get_comment_prefix(lang)
  local lines = {comment .. " ---"}
  
  -- Extract and add common metadata fields
  add_meta_line(lines, comment, "title", get_meta_field(meta, "title"))
  add_meta_line(lines, comment, "author", get_meta_field(meta, "author"))
  add_meta_line(lines, comment, "date", get_meta_field(meta, "date"))
  add_meta_line(lines, comment, "format", get_meta_field(meta, "format"))
  
  table.insert(lines, comment .. " ---")
  table.insert(lines, comment .. " ")
  
  return table.concat(lines, "\n") .. "\n"
end

--- Initialize code blocks storage for a language.
-- Creates an empty array for storing code blocks if one doesn't exist yet.
-- @param lang string The programming language identifier
local function init_language(lang)
  if not code_blocks[lang] then
    code_blocks[lang] = {}
    debug_log("Initialized storage for language: " .. lang)
  end
end

--- Read configuration from document metadata.
-- Extracts ripper-specific configuration options from extensions.ripper section.
-- Updates module-level variables: include_yaml, script_links_position, custom_base_name, debug.
-- @param meta table The document metadata
local function read_config(meta)
  if meta.extensions and meta.extensions.ripper then
    local config = meta.extensions.ripper
    
    if config["include-yaml"] ~= nil then
      include_yaml = config["include-yaml"]
    end
    
    if config["script-links-position"] then
      script_links_position = pandoc.utils.stringify(config["script-links-position"])
    end
    
    if config["output-name"] then
      custom_base_name = pandoc.utils.stringify(config["output-name"])
    end
    
    if config["debug"] ~= nil then
      debug = config["debug"]
    end
  end
  
  debug_log("Configuration loaded: include_yaml=" .. tostring(include_yaml) .. 
            ", script_links_position=" .. script_links_position .. 
            ", output_name=" .. tostring(custom_base_name or "auto") ..
            ", debug=" .. tostring(debug))
end

--- Determine the base output name for generated files.
-- Returns custom name if specified, otherwise uses the document filename.
-- @return string The base filename (without extension)
local function get_base_output_name()
  if custom_base_name then
    return custom_base_name
  else
    return pandoc.path.split_extension(PANDOC_STATE.output_file or "output")
  end
end

-- ============================================================================
-- 4. SECTION CREATION FUNCTIONS
-- ============================================================================

--- Create a Pandoc header with optional CSS classes.
-- @param level number The header level (1-6)
-- @param text string The header text
-- @param classes table|nil Optional array of CSS class names
-- @return pandoc.Header The created header element
local function create_header(level, text, classes)
  local header = pandoc.Header(level, {pandoc.Str(text)})
  if classes then
    header.classes = classes
  end
  return header
end

--- Create a bullet list of file links.
-- Converts file information into a Pandoc BulletList with clickable links.
-- @param files table Array of file info tables with 'filename' field
-- @return pandoc.BulletList Bullet list containing file links
local function create_file_list(files)
  local list_items = {}
  for _, file_info in ipairs(files) do
    local link = pandoc.Link(
      {pandoc.Str(file_info.filename)},
      file_info.filename
    )
    table.insert(list_items, {pandoc.Plain({link})})
  end
  return pandoc.BulletList(list_items)
end

--- Determine header level and classes based on output format.
-- For RevealJS, uses level 2 with 'scrollable' class.
-- For other formats, uses level 1 with no special classes.
-- @return number header_level The appropriate header level
-- @return table|nil header_classes Optional array of CSS classes
local function get_header_config()
  local is_revealjs = quarto.doc.is_format("revealjs")
  local header_level = is_revealjs and 2 or 1
  local header_classes = is_revealjs and {"scrollable"} or nil
  return header_level, header_classes
end

--- Create a section with links to generated script files.
-- Builds a complete section including header, description, and file links.
-- Header text is singular for 1 file, plural for multiple files.
-- @param files table Array of file info tables
-- @return table|nil Array of Pandoc blocks, or nil if suppressed/empty
local function create_script_links_section(files)
  if script_links_position == "none" or #files == 0 then
    debug_log("Skipping script links section (position=none or no files)")
    return nil
  end
  
  debug_log("Creating script links section with " .. #files .. " file(s)")
  
  local header_level, header_classes = get_header_config()
  
  -- Build the content blocks
  local content_blocks = {}
  
  -- Determine header text based on file count
  local header_text = #files == 1 and "Script file" or "Script files"
  
  -- Add header
  table.insert(content_blocks, create_header(header_level, header_text, header_classes))
  
  -- Add description
  table.insert(content_blocks, pandoc.Para({
    pandoc.Str("The code for this document can be found here:")
  }))
  
  -- Add file list
  table.insert(content_blocks, create_file_list(files))
  
  return content_blocks
end

-- ============================================================================
-- FILE WRITING FUNCTIONS
-- ============================================================================

--- Build complete file content for a programming language.
-- Combines YAML header (if enabled) with all code blocks for the language.
-- @param lang string The programming language identifier
-- @param blocks table Array of code block strings
-- @param meta table The document metadata
-- @return string Complete file content ready to write
local function build_file_content(lang, blocks, meta)
  debug_log("Building content for " .. lang .. " with " .. #blocks .. " code block(s)")
  
  local content = {}
  
  -- Add YAML header if requested
  local yaml_header = format_yaml_header(meta, lang)
  if yaml_header ~= "" then
    table.insert(content, yaml_header)
  end
  
  -- Add all code blocks for this language
  for i, code in ipairs(blocks) do
    if i > 1 then
      table.insert(content, "\n")  -- Separator between blocks
    end
    table.insert(content, code)
  end
  
  return table.concat(content, "\n") .. "\n"
end

--- Write a script file to disk.
-- Creates a file with the given content and logs the result.
-- @param filename string The full path/name of file to create
-- @param content string The file content to write
-- @param lang string The programming language (for tracking)
-- @return table|nil File info {filename, lang} on success, nil on failure
local function write_script_file(filename, content, lang)
  debug_log("Writing file: " .. filename .. " (" .. #content .. " bytes)")
  
  local file = io.open(filename, "w")
  if file then
    file:write(content)
    file:close()
    debug_log("Successfully wrote " .. filename)
    return {filename = filename, lang = lang}
  else
    debug_log("ERROR: Failed to create file: " .. filename)
    quarto.log.error("Failed to create file: " .. filename)
    return nil
  end
end

--- Process all collected code blocks and write script files.
-- Iterates through all languages, builds content, and writes files.
-- @param base_name string The base filename (without extension)
-- @param meta table The document metadata
-- @return table Array of successfully created file info tables
local function write_all_scripts(base_name, meta)
  debug_log("Writing all scripts with base name: " .. base_name)
  
  local generated_files = {}
  local lang_count = 0
  
  -- Count languages first for logging
  for _ in pairs(code_blocks) do
    lang_count = lang_count + 1
  end
  
  debug_log("Found code blocks in " .. lang_count .. " language(s)")
  
  for lang, blocks in pairs(code_blocks) do
    if #blocks > 0 then
      local extension = lang_extensions[lang]
      local filename = base_name .. extension
      local content = build_file_content(lang, blocks, meta)
      local file_info = write_script_file(filename, content, lang)
      
      if file_info then
        table.insert(generated_files, file_info)
      end
    end
  end
  
  debug_log("Successfully created " .. #generated_files .. " file(s)")
  
  return generated_files
end

-- ============================================================================
-- 6. BLOCK INSERTION FUNCTIONS
-- ============================================================================

--- Insert blocks at the top of the document.
-- Prepends blocks in reverse order to maintain correct sequence.
-- Note: We iterate in reverse because inserting at position 1 multiple times
-- would reverse the block order. Inserting [A,B,C] forward gives [C,B,A],
-- but inserting in reverse gives the correct [A,B,C] order.
-- @param doc pandoc.Pandoc The document object
-- @param blocks table Array of Pandoc blocks to insert
local function insert_at_top(doc, blocks)
  debug_log("Inserting " .. #blocks .. " block(s) at top of document")
  for i = #blocks, 1, -1 do
    table.insert(doc.blocks, 1, blocks[i])
  end
end

--- Insert blocks at the bottom of the document.
-- Appends blocks to the end of the document.
-- @param doc pandoc.Pandoc The document object
-- @param blocks table Array of Pandoc blocks to insert
local function insert_at_bottom(doc, blocks)
  debug_log("Inserting " .. #blocks .. " block(s) at bottom of document")
  for _, block in ipairs(blocks) do
    table.insert(doc.blocks, block)
  end
end

--- Insert blocks at a custom location marked by a div.
-- Searches for a div with the specified ID and replaces it with blocks.
-- Falls back to top insertion if div not found.
-- @param doc pandoc.Pandoc The document object
-- @param blocks table Array of Pandoc blocks to insert
-- @param div_id string The ID of the marker div to replace
local function insert_at_custom(doc, blocks, div_id)
  debug_log("Searching for custom position div: #" .. div_id)
  
  local found = false
  for i, block in ipairs(doc.blocks) do
    if block.t == "Div" and block.identifier == div_id then
      debug_log("Found custom position div at block " .. i .. ", inserting " .. #blocks .. " block(s)")
      
      -- Replace the div with our section blocks
      local new_blocks = {}
      for j = 1, i - 1 do
        table.insert(new_blocks, doc.blocks[j])
      end
      for _, section_block in ipairs(blocks) do
        table.insert(new_blocks, section_block)
      end
      for j = i + 1, #doc.blocks do
        table.insert(new_blocks, doc.blocks[j])
      end
      doc.blocks = new_blocks
      found = true
      break
    end
  end
  
  -- If not found, default to top
  if not found then
    quarto.log.warning("No div with id '" .. div_id .. "' found. Inserting at top.")
    debug_log("Custom position div not found, falling back to top insertion")
    insert_at_top(doc, blocks)
  end
end

--- Insert section blocks based on position setting.
-- Dispatches to appropriate insertion function based on configuration.
-- @param doc pandoc.Pandoc The document object
-- @param blocks table Array of Pandoc blocks to insert
-- @param position string Position indicator: "top", "bottom", or "custom"
local function insert_section_blocks(doc, blocks, position)
  debug_log("Insert position: " .. position)
  
  if position == "top" then
    insert_at_top(doc, blocks)
  elseif position == "bottom" then
    insert_at_bottom(doc, blocks)
  elseif position == "custom" then
    insert_at_custom(doc, blocks, "ripper-links")
  end
end

-- ============================================================================
-- FILTER FUNCTIONS
-- ============================================================================

--- Process document metadata.
-- Pandoc filter function that reads configuration and stores metadata.
-- @param meta table The document metadata
-- @return table The unmodified metadata
function Meta(meta)
  yaml_meta = meta
  read_config(meta)
  return meta
end

--- Process code blocks.
-- Pandoc filter function that collects code blocks by language.
-- @param block pandoc.CodeBlock The code block to process
-- @return pandoc.CodeBlock The unmodified code block
function CodeBlock(block)
  -- Get the language (classes[1] is typically the language)
  local lang = block.classes[1]
  
  if lang and lang_extensions[lang] then
    init_language(lang)
    
    -- Store just the code text
    table.insert(code_blocks[lang], block.text)
    debug_log("Collected code block for language: " .. lang .. " (" .. #block.text .. " bytes)")
  elseif lang then
    debug_log("Skipping unsupported language: " .. lang)
  end
  
  return block
end

--- Process the complete document.
-- Main filter function that writes script files and inserts links section.
-- @param doc pandoc.Pandoc The complete document
-- @return pandoc.Pandoc The modified document with script links section
function Pandoc(doc)
  debug_log("=== Starting document processing ===")
  
  -- Get the output filename base (without extension)
  if not output_name then
    output_name = get_base_output_name()
  end
  
  debug_log("Output base name: " .. output_name)
  
  -- Write script files
  local generated_files = write_all_scripts(output_name, yaml_meta)
  
  -- Create and insert script links section if needed
  if script_links_position ~= "none" and #generated_files > 0 then
    local section_blocks = create_script_links_section(generated_files)
    if section_blocks then
      insert_section_blocks(doc, section_blocks, script_links_position)
    end
  end
  
  debug_log("=== Document processing complete ===")
  
  return doc
end

-- ============================================================================
-- FILTER REGISTRATION
-- ============================================================================

--- Register Pandoc filters.
-- Returns the three filter functions in the order they should be applied.
-- @return table Array of filter tables for Pandoc
return {
  { Meta = Meta },
  { CodeBlock = CodeBlock },
  { Pandoc = Pandoc }
}