# directadmin::mail
class directadmin::mail(
  $mail_limit = 200,
  $sa_updates = true,
  $php_imap = false,
  $default_webmail = 'roundcube',
) {
  # File change: set up our e-mail limit
  file { '/etc/virtual/limit':
    ensure  => present,
    owner   => mail,
    group   => mail,
    mode    => '0644',

    # maximum e-mails per day, it needs quotes to ensure it gets 
    # read correctly, Hiera will set as an integer for example
    content => "${mail_limit}",

    # restart on change
    notify  => Service['exim'],
    require => Exec['directadmin-installer'],
  } ->
  # File change: /etc/virtual/limit_unknown
  file { '/etc/virtual/limit_unknown':
    ensure  => present,
    owner   => mail,
    group   => mail,
    mode    => '0644',
    content => 0,
    notify  => Service['exim'],
    require => Exec['directadmin-installer'],
  }

  # File: set the default webmail client
  file { '/var/www/html/webmail':
    ensure => link,
    target => "/var/www/html/${default_webmail}",
    require => Exec['directadmin-installer'],
  }
  # File_line: set the default /webmail alias
  file_line { 'httpd-alias-default-webmail':
    ensure => present,
    path => '/etc/httpd/conf/extra/httpd-alias.conf',
    line => "Alias /webmail /var/www/html/${default_webmail}",
    match => 'Alias \/webmail',
    notify => Service['httpd'],
    require => Exec['directadmin-installer'],
  }
  directadmin::config::set { 'webmail_link': value => $default_webmail, }

  # Install support for imap in php if required
  if $php_imap == true {
    exec { 'directadmin-download-php-imap':
      cwd     => '/root',
      command => 'wget -O /root/imap_php.sh files.directadmin.com/services/all/imap_php.sh && chmod +x /root/imap_php.sh',
      creates => '/root/imap_php.sh',
      require => Exec['directadmin-installer'],
    } ->
    exec { 'directadmin-install-php-imap':
      cwd     => '/root',
      command => '/root/imap_php.sh',
      unless  => 'php -i | grep -i c-client | wc -l | grep -c 1',
      require => Exec['directadmin-installer'],
      timeout => 0,
    }
  }

  # File_line: make sure the primary hostname is set in exim.conf
  # as we have seen some issues with CentOS 7 here.
  file_line { 'exim-set-primary-hostname':
    path  => "/etc/exim.conf",
    line  => "primary_hostname = ${::fqdn}",
    match => "# primary_hostname",
    notify  => Service['exim'],
    require => Exec['directadmin-installer'],
  }

  # SpamAssassin cron jobs
  if $sa_updates == true {
    $sa_cron = 'present'
  } else {
    $sa_cron = 'absent'
  }
  
  # Cron: daily update of SpamAssassin rules
  cron { 'exim-sa-update':
    ensure  => $sa_cron,
    command => '/usr/bin/sa-update && /sbin/service exim restart >/dev/null 2>&1',
    user    => root,
    hour    => 7,
    minute  => 5,
    require => Exec['directadmin-installer'],
  }
}
