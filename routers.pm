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
		#print Dumper \$self;
		$self->{mode} = "view" if (!$self->{mode});
		$self->{community} = "Ssgp17ifWk";
		unless (&check_available($self->{ip})){
			print "$self->{ip} host is dead\n";
			return 0;
		}
		$self->{hostname} = $self->get_hostname();
		$self->{model} = $self->get_model();

		switch ($self->{model}){
			case("zte"){
		$prompts{more} = "--More--";
		$prompts{more_cli}="($self->{hostname})|(--More--)";
		$prompts{cli}="$self->{hostname}";
			}
			case("cisco"){
		$prompts{more} = '--More--';
		$prompts{more_cli}="$self->{hostname}|--More--";
		$prompts{cli}="$self->{hostname}";
			}
			case("huawei"){
		$prompts{more} = '---- More ----';
		$prompts{cli}="$self->{hostname}";
		$prompts{more_cli}="$self->{hostname}|---- More ----";
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
			else{

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
		my $enable = $self->{enable};
		my $hostname = $self->{hostname};
		my $login = $self->{login} || "vision";
		my $pass = $self->{pass} || "rbyctler";
		#Input_log=>\*STDOUT, Output_log=>\*STDOUT); 
		#print Dumper \$self;
		print "connecting to $hostname\n";
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
					next;
					return;
				}
			}
		});#,	Input_log=>\*STDOUT, Output_log=>\*STDOUT);
		if ($self->{model} eq "cisco"){

			$self->{telnet}->open ("$ip");

			$self->{telnet}->waitfor(Match => "/Username:/", Timeout => 10, Errmode => sub {$self->position("cannot connect to $hostname");});
			$self->{telnet}->cmd(String => "$login", Prompt => "/Password:/", Timeout => 5, Errmode => sub {$self->position("\ncannot login on $hostname\n")});
			$self->{telnet}->cmd(String => "$pass", Prompt => "/$hostname#/", Timeout => 5, Errmode => sub {$self->position("\ncannot enter on $hostname\n")});
			if ($self->{mode} eq "config"){
				$self->{telnet}->cmd(String => "configure terminal", Prompt => "/$hostname.*#/", Timeout => 5, Errmode => sub {$self->position("\ncannot configure on $hostname\n")});
			}

		}elsif($self->{model} eq "zte"){

			$self->{telnet}->open ("$ip");

			$self->{telnet}->waitfor(Match => "/Username:/", Timeout => 10, Errmode => sub {$self->position("cannot connect to $hostname");});
			$self->{telnet}->cmd(String => "duty", Prompt => "/Password:/", Timeout => 5, Errmode=>sub {$self->position("cannot login to $hostname");});
			$self->{telnet}->cmd(String => "support", Prompt => "/$hostname/", Timeout => 5, Errmode => sub {$self->position("cannot enter on $hostname")});
			if ($self->{enable}){
				$self->{telnet}->cmd(String => "enable", Prompt => "/Password:/", Timeout => 5, Errmode => sub {$self->position("cannot enable on $hostname")});
			}
			if ($self->{mode} eq "config"){
				$self->{telnet}->cmd(String => "$enable", Prompt => "/$hostname#/", Timeout => 5, Errmode => sub {$self->position("\ncannot enable on $hostname\n")});
				$self->{telnet}->cmd(String => "configure terminal", Prompt => "/$hostname#/", Timeout => 5, Errmode => sub {$self->position("\ncannot configure on $hostname\n")});
			}
			
		}elsif($self->{model} eq "huawei"){

		$self->{telnet}->open ("$ip");

		$self->{telnet}->waitfor(Match => "/Username:/", Timeout => 10);
		$self->{telnet}->cmd(String => "noc", Prompt => "/Password:/", Timeout => 5, Errmode => sub {$self->position("\ncannot login on $hostname\n")});
		$self->{telnet}->cmd(String => "NocO3noC", Prompt => "/<$hostname>/", Timeout => 5, Errmode => sub {$self->position("\ncannot enter on $hostname\n")});
			if ($self->{mode} eq "config"){
				$self->{telnet}->cmd(String => "system-view", Prompt => "/[$hostname]/", Timeout => 5, Errmode => sub {$self->position("\ncannot configure on $hostname\n")});
			}

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
			#print Dumper \%prompts;
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
			$result.="$command\n";
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
