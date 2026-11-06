-- ripper tests. Run from the repo root: quarto pandoc lua path/to/qtest.lua
local t = require("qtest")

local site = {
  times = 2,
  output = "site/_site/analysis.html",
  read = { "site/analysis.R", "site/analysis.py", "site/analysis.js" },
}

-- Regression: scripts started with a knitr-spin `#' ---` header, so Quarto
-- took the generated analysis.R for a page on the next render, and its HTML
-- collided with analysis.qmd's.
t.test("a website renders a second time on top of its own scripts", function()
  local r = t.render("site", "html", site)
  r:succeeded()
end)

t.test("script headers use plain comments: # for R and Python, // for JavaScript", function()
  local r = t.render("site", "html", site)
  local expected = { ["site/analysis.R"] = "# ", ["site/analysis.py"] = "# ", ["site/analysis.js"] = "// " }
  for file, comment in pairs(expected) do
    local script = r.extra[file]
    t.ok(script, file .. " was written")
    t.eq(script:sub(1, #comment + 3), comment .. "---", file .. " header")
    t.contains(script, comment .. "title: My Analysis")
    t.not_contains(script, (comment:gsub(" $", "")) .. "'")
  end
end)
