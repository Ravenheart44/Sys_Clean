import os
 
os.system('find / \( -name smb-rav -o -name smb-time -o -name smb-pub \) -prune -o -type d -name "cache" 2>/dev/null | tee cache.txt')



