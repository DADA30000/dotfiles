if [[ "$(tty)" != "/dev/tty1" ]]
	 then
		 fbterm --font-size=16 --font-names="JetBrainsMono NF" --cursor-interval=0
		 paleofetch
fi
