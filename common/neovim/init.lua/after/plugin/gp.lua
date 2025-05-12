return {
  "robitx/gp.nvim",
  config = function()
    local conf = {
      providers = {
        anthropic = {
          endpoint = "https://api.anthropic.com/v1/messages",
        }
      },
      agents = {
        {
          provider = "anthropic",
          name = "ChatClaude-3-7-Sonnet",
          chat = true,
          command = false,
          model = { model = "claude-3-7-sonnet-latest", temperature = 0.8, top_p = 1 },
          system_prompt = require("gp.defaults").chat_system_prompt,
        },
        {
          provider = "anthropic",
          name = "CodeClaude-3-7-Sonnet",
          chat = false,
          command = true,
          model = { model = "claude-3-7-sonnet-latest", temperature = 0.8, top_p = 1 },
          system_prompt = require("gp.defaults").code_system_prompt,
        }
      }
    }
    require("gp").setup(conf)
  end,
}
