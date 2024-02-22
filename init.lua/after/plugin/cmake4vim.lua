vim.g.cmake_build_path_pattern = {"build/%s", "'linux-gnu.release'"}
-- vim.g.cmake_project_generator = "Ninja"
--vim.g.cmake_usr_args = "-G \"Ninja\""
vim.g.cmake_kits = { gcc = { generator="Ninja", cmake_build_args="--parallel 24"} }
vim.g.cmake_selected_kit = "gcc"
function runTwoVimCommands(command1, command2)
    -- only run the second command if the first one was successful
    if vim.fn.execute(command1) then
        vim.cmd(command2)
    end
end
common_cmake_args = "-j32 --output-on-failure --progress"
function buildAndLightTest()
    -- run utils#cmake#findBuildDir()
    local build_dir = vim.fn["utils#cmake#findBuildDir"]()
    vim.g.cmake_ctest_args = common_cmake_args .. "-j32 --label-regex light --build-generator Ninja --build-and-test " .. vim.fn.getcwd() .. " " .. build_dir
    vim.cmd("CTest");
end
function buildAndHeavyTest()
    vim.g.cmake_ctest_args = common_cmake_args .. " --label-regex heavy"
    vim.cmd("CTest");
end
-- set binding to run cmake
vim.keymap.set('n', '<leader>oc', '<cmd>CMakeRun<CR>', { noremap = true, silent = true })
vim.keymap.set('n', '<leader>ot', ':lua buildAndLightTest()<CR>', { noremap = true, silent = false })
vim.keymap.set('n', '<leader>oT', ':lua buildAndHeavyTest()<CR>', { noremap = true, silent = true })
vim.keymap.set('n', '<leader>os', '<cmd>Telescope cmake4vim select_target<CR>', { noremap = true, silent = true })

