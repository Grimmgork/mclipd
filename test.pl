use strict;
use Template::Mustache;
use HTTP::MultiPartParser;
use HTTP::Server::PSGI;

use constant PORT => 5000;
use constant HOST => "127.0.0.1";

sub parse_multipart_form_data {
	my $env = shift;
	my $name = shift;
	return (undef, undef, 0, []) unless $name;
	
	my ($content_type, $boundary) = $env->{CONTENT_TYPE} =~ /([a-zA-Z-\/]+);\s+(?:boundary=([0-9a-zA-Z'()+_,.\-\/:=?]+))$/;
	return undef unless $content_type eq "multipart/form-data";
	
	my $state = 0;
	my $size = 0;
	my $filename = undef;
	my $chunks = [];
	$content_type = undef;

	my $on_header = sub {
		my $headers = shift;
		my %hash = ();
		foreach (@$headers) { # create a hash of headers
			my ($header, $value) = $_ =~ /([a-zA-Z-]+):\s+(.+)/;
			$hash{$header} = $value;
		}

		# parse and dissect content disposition header
		my $disposition_values = dissect_header($hash{"Content-Disposition"});
		if (defined $disposition_values->{"form-data"} and $disposition_values->{"name"} eq $name)
		{
			$state = 1;
			$size = 0;
			$chunks = [];
			$content_type = $hash{"Content-Type"};
			$filename = $disposition_values->{"filename"};
		}
		else
		{
			$state = 0;
		}
	};

	my $on_body = sub {
		my $chunk = shift;
		if ($state == 1) {
			$size += length($chunk);
			push @$chunks, $chunk;
		}
	};

	my $parser = HTTP::MultiPartParser->new(
    	boundary  => $boundary,
    	on_header => $on_header,
   		on_body   => $on_body,
	);
	my $stream = $env->{"psgi.input"};
	my $read_chunk_from_stream = sub {
		my $stream = shift;
		my $chunk;
		read $stream, $chunk, 1048;
		return $chunk;
	};

	while (my $octets = $read_chunk_from_stream->($stream)) {
    	$parser->parse($octets);
	}
	
	$parser->finish;
	return ($content_type, $filename, $size, $chunks);
}

sub dissect_header {
	my $raw = shift;
	my %hash = ();
	my @matches = $raw =~ /(:?([a-zA-Z-]+)(:?="([^"]+)")?;?)/g;
	while (@matches) {
		shift @matches;
		my $name = shift @matches;
		shift @matches;
		my $value = shift @matches;
		$hash{$name} = $value || "";
	}
	return \%hash;
}

sub run_routes {
	my $env = shift;
	my $routes = shift;
	
	foreach (@$routes) {
		if ($_->[0] eq $env->{REQUEST_METHOD}) {
			if (ref($_->[1]) eq 'Regexp') {
				if (my @matches = $env->{REQUEST_PATH} =~ $_->[1]) {
					return $_->[2]->($env, \@matches);
				}
			} 
			else {
				return $_->[2]->($env)
			}
		}
	}

	return [404, [], []];
}

run_routes({ REQUEST_METHOD => "GET", REQUEST_PATH => "/data/2" }, [
	["GET", "/data/ui", sub {
		my $env = shift;
		my $matches = shift;
		printf $matches->[0], "\n";
		return [200, undef, undef];
	}],

	["GET", qr/\/data\/([1-9])$/, sub {
		my $env = shift;
		my $matches = shift;
		printf $matches->[0], "\n";
		return [200, undef, undef];
	}],

	["GET", qr/\/data\/([1-9])$/, sub {
		my $env = shift;
		my $matches = shift;
		printf $matches->[0], "\n";
		return [200, undef, undef];
	}],

	["GET", qr/\/data\/([1-9])$/, sub {
		my $env = shift;
		my $matches = shift;
		printf $matches->[0], "\n";
		return [200, undef, undef];
	}]
]);

exit;

sub app {
	my $env = shift;
	my ($content_type, $filename, $size, $chunks) = parse_multipart_form_data($env, "test");
	print $content_type, "\n";
	print $filename, "\n";
	print $size, "\n";
	print $chunks->[0], "\n";
	return [200, [], []];
}

my $server = HTTP::Server::PSGI->new(
    host => HOST,
    port => PORT,
    timeout => 120
);

$server->run(\&app);