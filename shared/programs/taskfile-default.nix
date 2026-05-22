{
  version = "3";
  
  includes = {
    dotfiles = {
      taskfile = "./dotfiles/Taskfile.yml";
      dir = "./dotfiles";
    };
  };
  
  tasks = {
    default = {
      cmds = [ "task --list-all" ];
      silent = true;
    };
  };
}
