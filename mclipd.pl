use HTTP::Server::PSGI;
use HTML::Template;

use JSON;

use constant PORT => 5000;
use constant HOST => "127.0.0.1";
use constant CHUNKSIZE => 2048;

use constant MIME_EMBEDABLE => [
	"text/plain",
	"application/json",
	"text/csv",
	"text/css"
];

my $server = HTTP::Server::PSGI->new(
    host => HOST,
    port => PORT,
    timeout => 120
);

$server->run(\&app);

my $INFO;    # ref to hash containing info about the clipped file
my $CONTENT; # array ref of chunked content of clipped file

sub app {
	my $env = shift;
	die "not suitable for multithreading/forking!\n" if $env->{"psgi.multithread"} or $env->{"psgi.multiprocess"};

	print $env->{REQUEST_METHOD}, " - ", $env->{PATH_INFO}, "\n";

	if($env->{PATH_INFO} eq '/ui'){
		my $embed = undef;
		$embed = $CONTENT->[0] if $INFO->{embed};
		my (undef,$min,$hour,$mday,$mon,$year) = localtime $INFO->{time};
		return res_template("ui.html", {
			filename => $INFO->{filename} || $INFO->{time},
			time     => sprintf("%02d-%02d-%02d %02d:%02d", $year, $mon, $mday, $hour, $min),
			embed    => $embed,
			size     => format_size($INFO->{length})
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
		# GET HEAD /
		if($env->{REQUEST_METHOD} eq 'GET' or $env->{REQUEST_METHOD} eq 'HEAD'){
			return res_status_message(204) unless $INFO; # 204 empty response!
			my $header = [
				"content-type"        => $INFO->{mimetype},
				"content-disposition" => "attachment; filename=" . $INFO->{filename},
				"cache-control"       => "no-cache",
				"content-length"      => $INFO->{length},
				"etag"                => $INFO->{time}
			];
			return [200, $header, $env->{REQUEST_METHOD} eq 'HEAD' ? [] : $CONTENT];
		}

		# POST /
		if($env->{REQUEST_METHOD} eq "POST"){
			my $filename;
			if(my $header = $env->{HTTP_CONTENT_DISPOSITION}){
				($filename) = $header =~ /\bfilename=\"(.+)\"/; # extract filename
				$filename =~ s/[^a-zA-Z0-9_.-]/_/g; # replace funny characters with _
			}
			
			my $mime = $env->{CONTENT_TYPE} || "application/octet-stream";

			my ($length, $chunks) = chop_stream($env->{"psgi.input"}, CHUNKSIZE);
			return res_status_message(400) unless $length;
			$CONTENT = $chunks;
			$INFO = {
				time     => time(),
				filename => $filename || $time,
				mimetype => $mime,
				length   => $length,
				plaintext => is_plaintext($CONTENT->[0]),
				embed    => (is_mime_embedable($mime) and length @$CONTENT == 1 and is_plaintext($CONTENT->[0]))
			};
			return res_status_message(200);
		}

		# DELETE /
		if($env->{REQUEST_METHOD} eq 'DELETE'){
			$INFO = undef;
			$CONTENT = undef;
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
	my $embedable = MIME_EMBEDABLE;
	return 1 if grep( /^$mime$/, @$embedable);
	return undef;
}

sub format_size {
	my $str = shift."b";
	my $units = ["kb", "mb", "gb", "tb", "pb"];
	my $lu = "b";
	foreach(@$units){
		last unless $str =~ s/(?<=\d)\d\d\d$lu$/$_/;
		$lu = $_;
	}
	return $str;
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
	return $length, \@chunks;
}

sub res_status_message {
	my $code = shift;
	my $message = {
		200 => "ok",
		404 => "not found",
		400 => "bad request"
	}->{$code.""};
	return [$code, ["content-type" => "text/plain"], ["$code - $message"]];
}

sub res_template {
	my $name = shift;
	my $args = shift;
	my $temp = HTML::Template->new(filename => "./templates/$name");
	$temp->param($args);
	return [200, ["content-type" => "text/html"], [$temp->output()]];
}