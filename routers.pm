#!/usr/bin/perl
{package routers;
#########################
use strict;
use Net::Telnet();
use Data::Dumper;
use Storable;
use Net::SNMP;
use Switch;
use Net::Ping;
#########################
	my @error;
	my $attempt;
	my %prompts;
	sub new {
		my $class = shift;
		my $self = shift;
		my %oids;
		bless $self, $class;
		$self->{mode} = "view" if (!$self->{mode});
		$self->{community} = "Ssgp17ifWk";
		unless (&check_available($self->{ip})){
			print "$self->{ip} host is dead\n";
			return 0;
			#next;
		}
		$self->{hostname} = $self->get_hostname();
		unless ($self->{hostname}) {
			warn "cannot resolve hostname for $self->{ip}"; 
			next;
		}
		$self->{model} = $self->get_model();
		unless ($self->{model}) {
			warn "cannot resolve hostname for $self->{ip}"; 
			next;
		}
		switch ($self->{model}){
			case("zte"){
		$prompts{more} = "--More--";
		$prompts{more_cli}="($self->{hostname})|(--More--)";
		$prompts{cli}="$self->{hostname}";
		$prompts{login}="Username:";
		$prompts{pass}="Password:";
		$self->{login}="duty";
		$self->{pass}="support";
			}
			case("cisco"){
		$prompts{more} = '--More--';
		$prompts{more_cli}="$self->{hostname}|--More--";
		$prompts{cli}="$self->{hostname}";
		$prompts{login}="Username:";
		$prompts{pass}="Password:";
		$self->{login}="vision" if (!$self->{login});
		$self->{pass}="rbyctler" if (!$self->{pass});
			}
			case("huawei"){
		$prompts{more} = '---- More ----';
		$prompts{cli}="$self->{hostname}";
		$prompts{more_cli}="$self->{hostname}|---- More ----";
		$prompts{login}="Username:";
		$prompts{pass}="Password:";
		$self->{login}="noc";
		$self->{pass}="NocO3noC";
			}
			case("dlink"){

			}
		}

		return $self;
	}
	sub check_available{
		my $ip= shift;
		my  $p = Net::Ping->new("external", 4);
		return 0 unless ($p->ping($ip));
		return 1;
	}
	sub get_by_snmp {
		my $self = shift;
		my @oid = shift;
		my $ip = $self->{ip};
		my $community = $self->{community};
		my ($session, $error) = Net::SNMP->session(Hostname => $ip, Timeout => 1, Community => "Ssgp17ifWk");
		return "session error: $error" unless ($session);
		my $result = $session->get_request(Varbindlist =>\@oid);
		$result = $result->{$oid[0]};
		return $result;
	}

	sub get_model{
		my $self = shift;
		my $model;
		my $result = $self->get_by_snmp("1.3.6.1.2.1.1.1.0");
		switch($result){
			case(/Cisco/){
				$model = "cisco";
			}
			case(/ZXR10/){
				$model = "zte";
			}
			case(/S5328C-EI-24S/){
				$model = "huawei";
			}
			case(/DXS/){
				$model= "dlink";
			}
			else{
				$model = "unknow model";
			}
		}
		return $model;
	}

	sub get_hostname {
		my $self = shift;
		my $result = $self->get_by_snmp("1.3.6.1.2.1.1.5.0");
		if ($result=~m/(.*)((?:\.freenet(?:\.com)?\.ua)|(?:\.o3\.ua))/){
			return $1;
		}else{
			return $result;
		}
	}

	sub connect {
		my $self = shift;
		my $ip = $self->{ip};
		my $hostname = $self->{hostname};
		my $login = $self->{login} || "vision";
		my $pass = $self->{pass} || "rbyctler";
		$self->{telnet} = new Net::Telnet (Timeout => 5, Errmode => sub {
			my $position;
			sub position {
				my $self = shift;
				$position = shift;
				if ($attempt<3) {
					$attempt++;
					warn "$position\n";
					push @{$self->{errors}}, "$self->{ip}: $position attempt $attempt";
					push @error, "$self->{ip}: $position";
					warn "failed connect attempt $attempt";		
					print "next trying\n";
					$self->connect();
				}else{
					print "Fail with $self->{hostname}";
					next;
					return;
				}
			}
		});#,	Input_log=>\*STDOUT, Output_log=>\*STDOUT);
		
		$self->{telnet}->open ("$ip");

		$self->{telnet}->waitfor(Match => "/$prompts{login}/", Timeout => 10, Errmode => sub {$self->position("cannot connect to $hostname");});
		$self->{telnet}->cmd(String => $self->{login}, Prompt => "/$prompts{pass}/", Timeout => 5, Errmode => sub {$self->position("\ncannot login on $hostname\n")});
		$self->{telnet}->cmd(String => $self->{pass}, Prompt => "/$prompts{cli}/", Timeout => 5, Errmode => sub {$self->position("\ncannot enter on $hostname\n")});
		
		if ($self->{enable}){
			$self->{telnet}->cmd(String => "enable", Prompt => "/$prompts{pass}/", Timeout => 5, Errmode => sub {$self->position("cannot enable on $hostname")});
			$self->{telnet}->cmd(String => "$self->{enable}", Prompt => "/$prompts{cli}/", Timeout => 5, Errmode => sub {$self->position("\ncannot enable on $hostname\n")});
		}

		if ($self->{mode} eq "config"){
			$self->{telnet}->cmd(String => "configure terminal", Prompt => "/$prompts{cli}/", Timeout => 5, Errmode => sub {$self->position("\ncannot configure on $hostname\n")});
		}

		return 1;
	}

	sub exec{
		my $self = shift;
		my @command = @_;
		my $hostname = $self->{hostname};
		
		for my $command (@command){
			my $array;
			$self->{telnet}->print ("$command");
			(my $arrays, my $match) = $self->{telnet}-> waitfor(Match => "/$prompts{more_cli}/", Timeout => 20, Errmode => sub {$self->position("trouble with command $command\n")});
			$array.=$arrays;
			while ($match =~ m/$prompts{more}/){
					$self->{telnet}->put(" ");
					($arrays, $match) = $self->{telnet}->waitfor(Match => "/$prompts{more_cli}/", Timeout => 3, Errmode => sub {$self->position("\n ################## something bad with scrolling ################\n")});
					$array .=$arrays;
					last if $match =~ m/$prompts{cli}/;
			}
			$array =~ s/$command\n//g;
			$self->{result}{$command}=$array;
		}
	}

	sub result {
		my $self = shift;
		my $command = shift;
		return $self->{result}->{$command} if ($command);
		my $result;
		for my $command (keys %{$self->{result}}){
			#$result.="$command\n";
			$result.=$self->{result}->{$command};
		}
		return $result;
	}
	sub close{
		my $self = shift;
		undef $self;
	}
	sub DESTROY { 
		my $self = shift; 
		#printf("$self dying at %s\n", scalar localtime); 
	}
}
1;
