# metaclip
a personal http clipboard in the cloud

mclipd.pl is a perl script representing said clipboard.

note:
mclipd does not implement access control and thus should be run behind
an authentication/authorization reverse proxy when exposed on the internet.

mclipd is synchronous in nature and processes requests one after the other.

## endpoints:

GET    /[file.txt]       returns the stored file
GET    /                 returns a redirect to the stored files name, returns the file if file is unnamed
DELETE /                 clears the clipboard
POST   /[file.txt]       upload a file, filename can be empty
