use Plack::Request;
use HTTP::Server::PSGI;
use HTTP::Status;
use HTML::Template;

use JSON;

use constant PORT => 5000;
use constant HOST => "127.0.0.1";

my $app = \&app;
my $server = HTTP::Server::PSGI->new(
    host => HOST,
    port => PORT,
    timeout => 120
);

$server->run($app);

my $INFO;
my $CONTENT;

sub app {
	my $env = shift;
	
	die "not suitable for multithread/-process!\n" if $env->{"psgi.multithread"} or $env->{"psgi.multiprocess"};

	# while ( ($k,$v) = each %$env ) {
    	# 	print "$k => $v\n";
	# }

	print $env->{REQUEST_METHOD}, " - ", $env->{PATH_INFO}, "\n";

	if($env->{PATH_INFO} eq '/ui'){
		my $embed = undef;
		if($INFO->{embed}){
			$embed = $CONTENT->[0];
		}
		return res_template("ui.html", {
			filename => $INFO->{filename},
			time => scalar localtime $INFO->{time},
			embed => $embed
		});
	}

	if($env->{PATH_INFO} eq '/ui/text'){
		return res_template("upfile.html");
	}

	if($env->{PATH_INFO} eq '/ui/file'){
		return res_template("uptext.html");
	}

	if($env->{PATH_INFO} eq '/info'){
		return [200, [], [encode_json $INFO]];
	}

	if($env->{PATH_INFO} eq '/'){
		# GET /
		if($env->{REQUEST_METHOD} eq 'GET'){
			return res_status_message(204) unless $INFO; # 204 empty response!
			return [200, ["Content-Disposition" => "attachment; filename=" . $INFO->{filename}, "content-type" => $INFO->{mimetype}, "X-Content-Type-Options" => "nosniff", "Cache-Control" => "no-cache"], $CONTENT];
		}

		# POST /
		if($env->{REQUEST_METHOD} eq "POST"){
			my $filename;
			if(my $header = $env->{HTTP_CONTENT_DISPOSITION}){
				($filename) = $header =~ /\bfilename=(.+)\b/; # extract filename
				$filename =~ s/[^a-zA-Z0-9_.-]/_/g; # remove funny characters and replace them with #
			}
			my $time = time();
			my $length = 0;
			($length, $CONTENT) = chop_stream($env->{"psgi.input"}, 1024);

			my $mime = $env->{CONTENT_TYPE};
			unless($mime){
				$mime = "application/octet-stream";
			}

			$INFO = {
				time     => $time,
				filename => $filename || $time,
				mimetype => $mime,
				length   => $length,
				embed    => (is_mime_embedable($mime) and length @$CONTENT == 1)
			};
			print $INFO->{filename}, "\n";
			return res_status_message(200);
		}

		# DELETE /
		if($env->{REQUEST_METHOD} eq 'DELETE'){
			$INFO = undef;
			print "clipboard dumped!\n";
			return res_status_message(200);
		}
	}

	return res_status_message(404);
}

sub is_plaintext {
	my $chunk = shift;
	return 0 if($chunk =~ /[^ -~\t\r\n]/);
	return 1;
}

sub is_mime_embedable {
	my $mime = shift;
	my $embed = [
		"text/plain",
		"application/json",
		"text/csv",
		"text/css"
	];
	return 1 if grep( /^$mime$/, @$embed );
	return undef;
}

sub chop_stream {
	my $fh = shift;
	my $chunksize = shift || 2048;
	my @chunks;
	my $length = 0;
	while(1){
		my $chunk;
		my $l = read $fh, $chunk, $chunksize;
		last unless $l;
		$length = $length + $l;
		push @chunks, $chunk;
	}
	return $length,  \@chunks;
}

sub res_status_message {
	my $code = shift;
	my $message = status_message($code);
	return [$code, ["content-type" => "text/plain"], ["$code - $message"]];
}

sub res_template {
	my $name = shift;
	my $args = shift;
	my $temp = HTML::Template->new(filename => "./templates/$name");
	$temp->param($args);
	return [200, ["content-type" => "text/html"], [$temp->output()]];
}