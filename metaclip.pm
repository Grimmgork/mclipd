package metaclip;

use HTTP::Server::PSGI;
use HTTP::MultiPartParser;
use Template::Mustache;
use JSON;
use threads::shared;

our @EXPORT = qw(app);

use constant CHUNKSIZE => 2048;
use constant MIME_EMBEDABLE => [
	"text/plain",
	"application/json",
	"text/csv",
	"text/css"
];

my $INFO; # ref to hash containing info about the clipped file
my $DATA; # array ref of chunked content of clipped file

my $LOCK; # used for thread synchronization

my $routes = [
	["GET", "/", sub {
		return res_temp_redirect('/ui');
	}],

	["GET", "/ui", sub {
		return res_template("templates/index");
	}],

	["GET", "/ui/upload", sub {
		return res_template("templates/upload");
	}],

	["POST", "/ui/data", sub {
		my $env = shift;
		my ($mime, $filename, $length, $chunks) = parse_multipart_form_data($env, "data");
		cmd_upload_data($mime, $filename, $length, $chunks);
		return res_template("templates/file");
	}],

	["GET", "/ui/file", sub {
		return res_template("templates/file");
	}],

	["GET", "/style.css", sub {
		return res_file("static/style.css");
	}],

	["GET", "/favicon.ico", sub {
		return res_file("static/favicon.ico");
	}],

	["GET", "/info", sub {
		return [200, [], [encode_json $INFO]];
	}],

	["GET", "/data", sub {
		my $env = shift;
		return res_no_content() unless $DATA;

		if($env->{QUERY_STRING}){
			unless($env->{QUERY_STRING} eq $INFO->{etag}){
				return res_no_content();
			}
		}
		my $header = [
			"content-type"        => $INFO->{mimetype},
			"cache-control"       => "no-cache",
			"content-length"      => $INFO->{length},
			"etag"                => $INFO->{etag},
			"content-disposition" => ($env->{QUERY_STRING} eq "attachment" ? "attachment" : "inline")."; filename=\"".$INFO->{filename}."\""
		];

		return [200, $header, $DATA];
	}],

	["POST", "/data", sub {
		my $env = shift;
		my $filename;
		if (my $header = $env->{HTTP_CONTENT_DISPOSITION}) {
			($filename) = $header =~ /\bfilename=\"(.+)\"/; # extract filename
		}
		my $mime = $env->{CONTENT_TYPE} || "application/octet-stream";
		my $stream = $env->{"psgi.input"};
		my ($length, $chunks) = chop_stream($stream);
		cmd_upload_data($mime, $filename, $length, $chunks);
		return res_status_message(200);
	}],

	["DELETE", "/data", sub {
		cmd_delete_data();
		return res_status_message(200);
	}]
];

sub app {
	my $env = shift;
	die "not suitable for forking webservers!\n" if $env->{"psgi.multiprocess"};
	print $env->{REQUEST_METHOD}, " - ", $env->{PATH_INFO}, "\n";

	my $res;
	eval {
		lock($LOCK) if $env->{"psgi.multithread"};  # synchronize threads if required
		$res = route($env, $routes);
	};
	if ($@) {
		print "#ERROR: $@";
		return res_status_message(500);
	}

	return $res;
}

sub route {
	my $env = shift;
	my $routes = shift;
	foreach (@$routes) {
		if ($_->[0] eq $env->{REQUEST_METHOD}) {
			if (ref($_->[1]) eq 'Regexp') {
				if (my @matches = $env->{PATH_INFO} =~ $_->[1]) {
					return $_->[2]->($env, \@matches);
				}
			}
			else {
				if ($env->{PATH_INFO} eq $_->[1]) {
					return $_->[2]->($env);
				}
			}
		}
	}
	return [404, ["Content-Type" => "text/plain"], ["not found."]];
}

sub cmd_upload_data {
	my $mime = shift;
	my $filename = shift;
	my $length = shift;
	my $chunks = shift;
	
	my $time = time();

	$filename =~ s/[^a-zA-Z0-9_.()-]/_/g; # replace funny characters with _

	$DATA = $chunks;
	$INFO = {
		time     => $time,
		filename => $filename || $time,
		mimetype => $mime || "application/octet-stream",
		length   => $length,
		embed    => (is_mime_embedable($mime) and @$DATA == 1 and is_plaintext($DATA->[0])),
		etag     => $time
	};
}

sub cmd_delete_data {
	$DATA = undef;
	$INFO = undef;
}

sub parse_multipart_form_data {
	my $env = shift;
	my $name = shift;
	return (undef, undef, 0, []) unless $name;
	
	my ($mime, $boundary) = $env->{CONTENT_TYPE} =~ /([a-zA-Z-\/]+);\s+(?:boundary=([0-9a-zA-Z'()+_,.\-\/:=?]+))$/;
	return (undef, undef, 0, []) unless $mime eq "multipart/form-data";
	
	my $state = 0;
	my $size = 0;
	my $filename = undef;
	my $chunks = [];
	$mime = undef;

	my $on_header = sub {
		my $headers = shift;
		my %hash = ();
		# create a hash of headers
		foreach (@$headers) { 
			my ($header, $value) = $_ =~ /([a-zA-Z-]+):\s+(.+)/;
			$hash{$header} = $value;
		}

		# parse and dissect content disposition header
		my $disposition_values = dissect_header($hash{'Content-Disposition'});
		if (defined $disposition_values->{'form-data'} and $disposition_values->{'name'} eq $name)
		{
			# prepare for reading form data
			$state = 1;
			$size = 0;
			$chunks = [];
			$mime = $hash{'Content-Type'};
			$filename = $disposition_values->{'filename'};
		}
		else
		{
			# skip reading form data
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
	my $stream = $env->{'psgi.input'};
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
	return ($mime, $filename, $size, $chunks);
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

sub is_plaintext {
	my $chunk = shift;
	return undef if($chunk =~ /[^ -~\t\r\n]/);
	return 1;
}

sub is_mime_embedable {
	my $mime = shift;
	my $embedable = MIME_EMBEDABLE;
	return 1 if grep( /^$mime$/, @$embedable);
	return undef;
}

sub format_size {
	my $str = (shift || 0)."b";
	my $units = ["kb", "mb", "gb", "tb", "pb"];
	my $lu = "b";
	foreach(@$units){
		last unless $str =~ s/(?<=\d)\d\d\d$lu$/$_/;
		$lu = $_;
	}
	return $str;
}

sub dotdot {
	my $path = shift;
	my @segments = split("/", $path);
	splice(@segments, -1);
	return join("/", @segments);
}

sub chop_stream {
	my $fh = shift;
	my $chunksize = shift || 2048;
	my @chunks;
	my $length = 0;
	while (1) {
		my $chunk;
		my $l = read $fh, $chunk, $chunksize;
		last unless $l;
		$length = $length + $l;
		push @chunks, $chunk;
	}
	return $length, \@chunks;
}

sub default_template_context {
	my $embed = undef;
	$embed = $DATA->[0] if $INFO->{embed};
	my (undef, $min, $hour, $mday, $mon, $year) = localtime $INFO->{time};
	return {
		filename => $INFO->{filename},
		time     => sprintf("%02d-%02d-%02d %02d:%02d", $year+1900, $mon, $mday, $hour, $min),
		embed    => $embed,
		size     => format_size($INFO->{length}),
		etag     => $INFO->{etag}
	};
}

my %template_cache = {};
sub render_mustache_template {
	my $template = shift;
	my $context = shift || default_template_context();

	my $mustache = $template_cache{$template};
	unless ($mustache)
	{
		$mustache = Template::Mustache->new(
			template_path => "$template.mustache",
			partials_path => dotdot($template)
		);
		$template_cache{$template} = $mustache;
	}

	return $mustache->render($context);
}

sub res_temp_redirect {
	my $location = shift;
	return [307, ["Location" => $location], []];
}

sub res_status_message {
	my $code = shift;
	my $message = {
		200 => "ok",
		404 => "not found",
		400 => "bad request",
		500 => "internal server error :["
	}->{"$code"};
	unless($message){
		$message = shift || "";
	} 
	return [$code, ["content-type" => "text/plain"], ["$code - $message"]];
}

sub res_ok {
	return [200, shift || [], shift || []];
}

sub res_no_content {
	return [204, [], []];
}

sub res_template {
	my $name = shift;
	my $context = shift;
	return [200, ["content-type" => "text/html"], [render_mustache_template($name, $context)]];
}

sub res_file {
	my $file = shift;
	return res_status_message(404) unless -e $file;
	open(my $fh, "<", $file) or die "cannot read file $file\n";
	my ($length, $chunks) = chop_stream($fh, CHUNKSIZE);
	close $fh;
	return [200, ['cache-control' => 'max-age=3600'], $chunks];
}