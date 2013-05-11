=head1 B<Insteon::RemoteLinc>

=head2 SYNOPSIS

Configuration:

Depending on your device and your settings, your remote may offer 1, 4, or 8
groups.  Your configuration should vary depeninding on you remote style.

In user code:

   use Insteon::RemoteLinc;
   $remote_1 = new Insteon::RemoteLinc('12.34.56:01',$myPLM);
   $remote_2 = new Insteon::RemoteLinc('12.34.56:02',$myPLM);
   $remote_3 = new Insteon::RemoteLinc('12.34.56:03',$myPLM);
   $remote_4 = new Insteon::RemoteLinc('12.34.56:04',$myPLM);

In items.mht:

   INSTEON_REMOTELINC, 12.34.56:01, $remote_1, $remote_group
   INSTEON_REMOTELINC, 12.34.56:02, $remote_2, $remote_group
   INSTEON_REMOTELINC, 12.34.56:03, $remote_3, $remote_group
   INSTEON_REMOTELINC, 12.34.56:04, $remote_4, $remote_group

=head2 DESCRIPTION

Provides basic support for Insteon RemoteLinc models 1 and 2.  Basic support
includes, linking and receiving set commands from the device.  More advanced
support is offered for RemoteLinc 2 in the form of battery level notifications.

MisterHouse is only able to communicate with a RemoteLinc when it is in "awake
mode."  The device is in "awake mode" while in its linking state.  To put the 
RemoteLinc into "awake mode", follow the instructions for placing the device into
linking mode.  In short, the instructions are to hold down the set button for 4-10
seconds until you hear a beep and see the light flash.  The RemoteLinc will now
remain in "awake mode" for approximately 4 minutes.

To scan the link table, sync links, or set settings on the device, the RemoteLinc
must first be put into "awake mode."

=head2 INHERITS

B<Insteon::BaseDevice>, B<Insteon::DeviceController>

=head2 METHODS

=over

=cut

package Insteon::RemoteLinc;

use strict;
use Insteon::BaseInsteon;

@Insteon::RemoteLinc::ISA = ('Insteon::BaseDevice','Insteon::DeviceController');

my %message_types = (
	%Insteon::BaseDevice::message_types,
	bright => 0x15,
	dim => 0x16,
	extended_set_get => 0x2e
);

sub new
{
	my ($class,$p_deviceid,$p_interface) = @_;

	my $self = new Insteon::BaseDevice($p_deviceid,$p_interface);
        $$self{message_types} = \%message_types;
	if ($self->is_root){
		$self->restore_data('battery_timer', 'last_battery_time', 
		'low_battery_level', 'low_battery_event');
	}
	bless $self,$class;
	return $self;
}

sub set
{
	my ($self,$p_state,$p_setby,$p_response) = @_;
	return if &main::check_for_tied_filters($self, $p_state);

	# Override any set_with_timer requests
	if ($$self{set_timer}) {
		&Timer::unset($$self{set_timer});
		delete $$self{set_timer};
	}

	# if it can't be controlled (i.e., a responder), then don't send out any signals
	# motion sensors seem to get multiple fast reports; don't trigger on both
        my $setby_name = $p_setby;
        $setby_name = $p_setby->get_object_name() if (ref $p_setby and $p_setby->can('get_object_name'));
	if (not defined($self->get_idle_time) or $self->get_idle_time > 1 or $self->state ne $p_state) {
		&::print_log("[Insteon::RemoteLinc] " . $self->get_object_name()
			. "::set_receive($p_state, $setby_name)") if $main::Debug{insteon};
		$self->set_receive($p_state,$p_setby);
	} else {
		&::print_log("[Insteon::RemoteLinc] " . $self->get_object_name()
			. "::set_receive($p_state, $setby_name) deferred due to repeat within 1 second")
			if $main::Debug{insteon};
	}
	return;
}

=item C<set_awake_time([0-255 seconds])>

Only available for RemoteLinc 2 models.

Sets the amount of time, in seconds, that the RemoteLinc will remain "awake" 
after sending a command.  MH uses the awake time to send battery level requests
to the device.  If the device is not responding to the battery level requests,
consider increasing this value.  However, keep in mind that a longer awake time
will result in more battery usage.

The factory setting is 4 seconds, 10 seconds seems to work with MisterHouse 
without causing adverse battery drain.

=cut

sub set_awake_time {
	my ($self, $awake) = @_;
	$awake = sprintf("%02x", $awake);
	my $root = $self->get_root();
	my $extra = '000102' . $awake . '0000000000000000000000';
	$$root{_ext_set_get_action} = "set";
	my $message = new Insteon::InsteonMessage('insteon_ext_send', $root, 'extended_set_get', $extra);
	$root->_send_cmd($message);
	return;
}

=item C<get_extended_info()>

Only available for RemoteLinc 2 models.

Requests the status of various settings on the device.  Currently this is only
used to obtain the battery level.  If the device is awake, the battery level 
will be printed to the log.

You likely do not need to directly call this message, rather MisterHouse will issue
this request when it sees activity from the device and the C<set_battery_timer()> has 
expired.

=cut

sub get_extended_info {
	my ($self) = @_;
	my $root = $self->get_root();
	my $extra = '000100000000000000000000000000';
	$$root{_ext_set_get_action} = "get";
	my $message = new Insteon::InsteonMessage('insteon_ext_send', $root, 'extended_set_get', $extra);
	$root->_send_cmd($message);
	return;
}

=item C<set_battery_timer([minutes])>

Only available for RemoteLinc 2 models.

Sets the minimum amount of time between battery level requests.  When this time
expires, Misterhouse will request the battery level from the device the next time
MisterHouse sees activity from the device.  Misterhouse will continue to request
the battery level until it gets a response from the device.

Setting to 0 will disable automatic battery level requests.  1440 equals a day.

This setting will be saved between MisterHouse reboots.

=cut

sub set_battery_timer {
	my ($self, $minutes) = @_;
	my $root = $self->get_root();
	$$root{battery_timer} = sprintf("%u", $minutes);
	::print_log("[Insteon::RemoteLinc] Set battery timer to ".
		$$root{battery_timer}." minutes");
	return;
}

=item C<set_low_battery_level([0.00])>

Only available for RemoteLinc 2 models.

If the battery level falls below this voltage, the C<battery_low_event()> 
command is run.  The theoretical maximum voltage of the battery is 3.70 volts.
The recommended low battery setting by Insteon is 3.26 volts.

Setting to 0 will prevent any low battery events from occuring.  

This setting will be saved between MisterHouse reboots.

=cut

sub set_low_battery_level {
	my ($self, $level) = @_;
	my $root = $self->get_root();
	$$root{low_battery_level} = sprintf("%.2f", $level);
	::print_log("[Insteon::RemoteLinc] Set low battery level to ".
		$$root{low_battery_level}." volts.");
	return;
}

=item C<battery_low_event([cmd_to_eval])>

Only available for RemoteLinc 2 models.

If the battery level falls below the percentage defined by C<set_low_battery_level()> 
this command is evaluated.  Works very similar to a C<Generic_Item::tie_event()>
eval.

Example:

   $remote->battery_low_event('speak "Warning, Remote battery is low."');

See C<test_tie.pl> for more examples.

This setting will be saved between MisterHouse reboots.

=cut

sub battery_low_event {
	my ($self, $eval) = @_;
	my $root = $self->get_root();
	$$root{low_battery_event} = $eval;
	::print_log("[Insteon::RemoteLinc] Set low battery event.");
	return;
}

sub _is_battery_time_expired {
	my ($self) = @_;
	my $root = $self->get_root();
	if ($$root{battery_timer} > 0 && 
		(time - $$root{last_battery_time}) > ($$root{battery_timer} * 60)) {
		return 1;
	}
	return 0;
}

sub _is_battery_low {
	my ($self, $voltage) = @_;
	my $root = $self->get_root();
	if ($$root{low_battery_level} > 0 && 
		($$root{low_battery_level} > $voltage)) {
		return 1;
	}
	return 0;
}

sub _process_message {
	my ($self,$p_setby,%msg) = @_;
	my $clear_message = 0;
	my $root = $self->get_root();
	if ($msg{command} eq 'link_cleanup_report' && $self->_is_battery_time_expired){
		#Queue an get_extended_info request
		$self->get_extended_info();
	}
	if ($msg{command} eq "extended_set_get" && $msg{is_ack}){
		$self->default_hop_count($msg{maxhops}-$msg{hopsleft});
		#If this was a get request don't clear until data packet received
		main::print_log("[Insteon::RemoteLinc] Extended Set/Get ACK Received for " . $self->get_object_name) if $main::Debug{insteon};
		if ($$self{_ext_set_get_action} eq 'set'){
			main::print_log("[Insteon::RemoteLinc] Clearing active message") if $main::Debug{insteon};
			$clear_message = 1;
			$$self{_ext_set_get_action} = undef;
			$self->_process_command_stack(%msg);	
		}
	}
	elsif ($msg{command} eq "extended_set_get" && $msg{is_extended}) {
		if (substr($msg{extra},0,6) eq "000001") {
			$self->default_hop_count($msg{maxhops}-$msg{hopsleft});
			#D10 = Battery;
			my $voltage = (hex(substr($msg{extra}, 20, 2))/50);
			main::print_log("[Insteon::RemoteLinc] The battery level ".
				"for device ". $self->get_object_name . " is: ".
				$voltage . " of 3.70 volts.");
			$$root{last_battery_time} = time;
			if ($self->_is_battery_low($voltage)){
				main::print_log("[Insteon::RemoteLinc] The battery level ".
					"is below the set threshold running low battery event.");
				package main;
					eval $$root{low_battery_event};
					::print_log("[Insteon::RemoteLinc] " . $self->{device}->get_object_name . ": error during low battery event eval $@")
						if $@;
				package Insteon::RemoteLinc;
			}
			$clear_message = 1;
			$self->_process_command_stack(%msg);
		} else {
			main::print_log("[Insteon::RemoteLinc] WARN: Corrupt Extended "
				."Set/Get Data Received for ". $self->get_object_name) if $main::Debug{insteon};
		}
	}
	else {
		$clear_message = $self->SUPER::_process_message($p_setby,%msg);
	}
	return $clear_message;
}

sub is_responder
{
   return 0;
}

=back

=head2 INI PARAMETERS

None.

=head2 AUTHOR

Bruce Winter, Gregg Limming, Kevin Robert Keegan

=head2 SEE ALSO



=head2 LICENSE

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

=cut
1