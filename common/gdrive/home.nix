{pkgs, ...}:
{
  home.packages = [ pkgs.rclone ];
  xdg.configFile."rclone/rclone.conf".text = ''
    [gdrive]
    type = drive
    client_id = 861026121581-ikf0ku841ifammeebbdah8agaqh3j13i.apps.googleusercontent.com
    scope: drive,drive.file,drive.metadata.readonly
    '';
}
