
[~]      access should be authenticated with apikey (via reverse proxy?)
[mclip]  host:port

~ get    mclip	          -> redirect mclip/[secret location]/file.txt (reveals the secret url to the ressource only works once)
~ post   mclip/file.txt   -> upload resource to clipboard with name
~ delete mclip            -> clears the clipboard

  get    mclip/[secret location]/file.txt
