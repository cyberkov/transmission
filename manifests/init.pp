# = Class: transmission
# 
# This class installs/configures/manages the transmission-daemon bittorrent client.
# 
# == Parameters: 
#
# $download_dir:: The directory where the files have to be downloaded. Defaults to +$config_path/downloads+.
# $incomplete_dir:: The temporary directory used to store incomplete files. Disabled when the option is not set (this is the default).
# $web_path:: URL path for the web client (without trailing /). Disabled when the option is not set (this is the default).
# $web_port:: The port the web server is listening on. Defaults to +9091+.
# $web_user:: The web client login name. Defaults to +transmission+.
# $web_password:: The password of the web client user (default: <none>)
# $web_whitelist:: An array of IP addresses. This list define which machines are allowed to use the web interface. It is possible to use wildcards in the addresses. By default the list is empty.
# $blocklist_url:: An url to a block list (default: <none>)
# $package_name:: name of the package. Default to 'transmission-daemon'
# $transmission_user:: default 'transmission'
# $transmission_group:: default 'transmission'
# $service_name:: default = $package_name
#
# == Requires: 
# 
# Nothing.
# 
# == Sample Usage:
#
#  class {'transmission':
#    download_dir => "/downloads",
#    incomplete_dir => "/tmp/downloads",
#    web_path => "/bittorrent", ### Corrected
#    web_port => 9091,
#    web_whitelist => ['127.0.0.1'],
#    blocklist_url => 'http://list.iblocklist.com/?list=bt_level1',
#  }
#

class transmission (
  $config_path = undef,
  $download_dir = '/downloads',
  $incomplete_dir = undef,
  $blocklist_url = undef,
  $web_path = undef,
  $web_port = 9091,
  $web_user = 'transmission',
  $web_password = undef,
  $web_whitelist = undef,
  $package_name = 'transmission-daemon',
  $transmission_user = 'transmission',
  $transmission_group = 'transmission',
  $service_name = undef,
  ) {

  if ($service_name == undef) {
    $_service_name = $package_name
  } else {
    $_service_name = $service_name
  }

  package { 'transmission-daemon':
    name   => $package_name,
    ensure => installed,
  }

  # Find out the name of the transmission user/group
  # ## // Moved to calling class //

  # Helper. To circumvent transmission's bad habit of rewriting 'settings.json' every now and then.
  # Even tried to write protect settings.json, but no luck so far.
  exec { 'stop-daemon':
    command => "service $package_name stop",
    path    => ['/sbin', '/usr/sbin'],
    require => Package['transmission-daemon'], # Needs to be installed before we can try to stop it
  }

  # Transmission should be able to read the config dir
  file { $config_path:
    ensure   => directory,
    group    => $transmission_group,            # We only set the group (the dir could be owned by root or someone ele)
    mode     => 'g+rx',                         # Make sure transmission can access the config dir
    require  => Package['transmission-daemon'], # Make sure that the package had the opportunity to create the directory first
  }

  # The settings file should follow our template
  file { 'settings.json':
    path    => "${config_path}/settings.json",
    ensure  => file,
    require => [File[$config_path],Exec['stop-daemon']],
    content => template("${module_name}/settings.json.erb"),
    mode    => 'u+rw',          # Make sure transmisson can r/w settings
  }

  # Transmission should use the settings in ${config_path}/settings.json *only*
  # This is ugly, but necessary
  file {['/etc/default/transmission','/etc/default/transmission-daemon','/etc/sysconfig/transmission','/etc/sysconfig/transmission-daemon']:
    ensure  => absent,                         # Kill the bastards
    require => Package['transmission-daemon'], # The package has to be installed first. Otherwise this would be sheer folly.
    before  => Service['transmission-daemon'], # After this is fixed, we can handle the service
  }
    
  # Manage the download directory.  Creating parents will be taken care of "upstream" (in the calling class)
  file { $download_dir:
    ensure  => directory,
    recurse => true,
    owner   => $transmission_user,
    group   => $transmission_group,
    mode    => 'ug+rw,u+x',
    require => Package['transmission-daemon'], # Let's give the installer a chance to create the directory and user before we manage this dir
  }

  # directory for partial downloads
  if $incomplete_dir {
    file { $incomplete_dir:
      ensure  => directory,
      recurse => true,
      owner   => $transmission_user,
      group   => $transmission_group,
      mode    => 'ug+rw,u+x',
      require => Package['transmission-daemon'],
    }
  }

  # Keep the service running
  service { 'transmission-daemon':
    name => $_service_name,
    ensure => running,
    enable => true,
    hasrestart => true,
    hasstatus => true,
  }

  # Keep blocklist updated
  if $web_path and $blocklist_url {
    if $web_password {
      $opt_auth = " --auth ${web_user}:${web_password}"
    }
    else
    {
      $opt_auth = ""
    }
    cron { 'update-blocklist':
      command => "/usr/bin/transmission-remote http://127.0.0.1:${web_port}${web_path}${opt_auth} --blocklist-update 2>&1 > /tmp/blocklist-update.log",
      user => root,
      hour => 2,
      minute => 0,
      require => Package['transmission-daemon'],
    }
  }
}
