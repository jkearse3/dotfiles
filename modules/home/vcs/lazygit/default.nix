{
  ...
}:
{
  programs.lazygit = {
    enable = true;
    settings = {
      os = {
        edit = "nvim --server $NVIM --remote-send '<cmd>close<cr><cmd>lua edit_from_lazygit({{filename}})<cr>'";
        editAtLine = "nvim --server $NVIM --remote-send '<cmd>close<cr><cmd>lua edit_from_lazygit({{filename}},{{line}})<cr>'";
      };
    };
  };
}
