local code_blocks = {}
local yaml_meta = nil
local include_yaml = true
local output_name = nil

-- Language to file extension mapping
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

-- Comment style mapping for different languages
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

-- Get comment prefix for a language
local function get_comment_prefix(lang)
  return comment_styles[lang] or "#'"
end

-- Convert YAML metadata to commented lines
local function format_yaml_header(meta, lang)
  if not include_yaml then
    return ""
  end
  
  local comment = get_comment_prefix(lang)
  local lines = {comment .. " ---"}
  
  -- Extract common metadata fields
  if meta.title then
    local title = pandoc.utils.stringify(meta.title)
    table.insert(lines, comment .. " title: " .. title)
  end
  
  if meta.author then
    local author = pandoc.utils.stringify(meta.author)
    table.insert(lines, comment .. " author: " .. author)
  end
  
  if meta.date then
    local date = pandoc.utils.stringify(meta.date)
    table.insert(lines, comment .. " date: " .. date)
  end
  
  if meta.format then
    local format = pandoc.utils.stringify(meta.format)
    table.insert(lines, comment .. " format: " .. format)
  end
  
  table.insert(lines, comment .. " ---")
  table.insert(lines, comment .. " ")
  
  return table.concat(lines, "\n") .. "\n"
end

-- Initialize code blocks storage for a language
local function init_language(lang)
  if not code_blocks[lang] then
    code_blocks[lang] = {}
  end
end

-- Process Meta block to get configuration and metadata
function Meta(meta)
  yaml_meta = meta
  
  -- Check for ripper configuration under extensions.ripper
  if meta.extensions and meta.extensions.ripper then
    local config = meta.extensions.ripper
    
    if config["include-yaml"] ~= nil then
      include_yaml = config["include-yaml"]
    end
  end
  
  return meta
end

-- Process code blocks
function CodeBlock(block)
  -- Get the language (classes[1] is typically the language)
  local lang = block.classes[1]
  
  if lang and lang_extensions[lang] then
    init_language(lang)
    
    -- Store just the code text
    table.insert(code_blocks[lang], block.text)
  end
  
  return block
end

-- Write all collected code to separate files
function Pandoc(doc)
  -- Get the output filename base (without extension)
  if not output_name then
    output_name = pandoc.path.split_extension(PANDOC_STATE.output_file or "output")
  end
  
  -- Write a file for each language
  for lang, blocks in pairs(code_blocks) do
    if #blocks > 0 then
      local extension = lang_extensions[lang]
      local filename = output_name .. extension
      
      -- Build file content
      local content = {}
      
      -- Add YAML header if requested
      local yaml_header = ""
      if include_yaml and yaml_meta then
        yaml_header = format_yaml_header(yaml_meta, lang)
      end
      
      -- Only add yaml_header if it's not empty
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
      
      -- Write to file
      local file = io.open(filename, "w")
      if file then
        file:write(table.concat(content, "\n"))
        file:write("\n")  -- Ensure file ends with newline
        file:close()
        
        -- Log the file creation
        quarto.log.output("Created: " .. filename)
      else
        quarto.log.error("Failed to create file: " .. filename)
      end
    end
  end
  
  return doc
end

-- Return the filter functions
return {
  { Meta = Meta },
  { CodeBlock = CodeBlock },
  { Pandoc = Pandoc }
}