# Category=Home_Network
#
#@ Sends Notification message to KODI

# The following config parameters should be in mh.private.ini or mh.ini

# kodi_notify_address=192.168.1.50:8080    ( <IP of KODI server>:<port> )  Specify multiple addresses with ,
# kodi_timeout=5000                        ( amount of time to display message on screen -- in milliseconds )
# kodi_title=MisterHouse                   ( Title of notification box )
# kodi_image=http://192.168.1.5/ia5/mh.png ( Image to display next to message.. I copied favicon.ico .. Not all skins support images )

# http://misterhouse.wikispaces.com/KODI+Notifications

use LWP::UserAgent;

$v_kodi_osd = new  Voice_Cmd("Test KODI Notify");

# noloop=start
my $kodi_address = $config_parms{kodi_notify_address};

# noloop=stop

#Tell MH to call our routine each time something is spoken
&Speak_pre_add_hook(\&kodi_yac,1) if $Reload;
$v_kodi_yac_test   =  new Voice_Cmd('Test KODI yac connection', undef, 1);

if ($state = said $v_kodi_yac_test) {
	&kodi_yac(text=>"This is a test from misterhouse to KODI");
}

# Notify the on startup / restart
if ($Startup) {
	print_log("System Restarted, Notifying KODI") if $Debug{kodi};
	display_kodiosd("$config_parms{kodi_title}", "Misterhouse has been restarted", $config_parms{kodi_timeout}, "$config_parms{kodi_image}");

        net_mail_send(
                        subject => "MisterHouse: MH has been restarted",
                        text    => "Misterhouse has been restarted $Time_Date"
                     );

}

if (said $v_kodi_osd) {
# Send a test notification to the configured KODI instance
	print_log("Sending test notification") if $Debug{kodi};
	display_kodiosd("$config_parms{kodi_title}", "This is a test notification!!", $config_parms{kodi_timeout}, "$config_parms{kodi_image}");
}

sub kodi_yac() {
	my %parms = @_;
	print "KODI message sent";
	print "----------------";
	display_kodiosd("$config_parms{kodi_title}", "$parms{text}", $config_parms{kodi_timeout}, "$config_parms{kodi_image}");
	return;
}

sub display_kodiosd {
	my ($title, $text, $timeOut, $image) = @_;

	unless($kodi_address){
		print_log("kodi_address has not been set in mh.ini, Unable to notify KODI.");
		return;
	}

# Change spaces to HTML space codes
	$title =~ s/ /%20/g;
	$text =~ s/ /%20/g;

# Cycle through "kodi_notify_address"(s)

	my @values = split(',', $kodi_address);
	foreach my $val (@values) {

		print_log("Sending notification to KODI at http://".$val."/jsonrpc") if $Debug{kodi};
# Doesnt support authentication (Yet)

		my $url = 'http://' .$val.'/jsonrpc?request={"jsonrpc":"2.0","method":"GUI.ShowNotification","params":{"title":"'.$title.'"  , "message":"'.$text.'"  ,  "displaytime":'.$timeOut.'  ,   "image":"'.$image.'"        },"id":1}';

		my $ua = new LWP::UserAgent;
		my $req = new HTTP::Request GET => $url;
		my $res = $ua->request($req);
	}
}
