exec:

compile:

install: bmount.sh
	sudo ls > /dev/null
	sudo cp bmount.sh /usr/bin/bmount
	sudo chmod +x /usr/bin/bmount
	sudo mkdir -p /etc/bmount/volumes/examples
	sudo cp ./examples/* /etc/bmount/volumes/examples/
	sudo mkdir -p /var/bmount/loopback

uninstall:
	sudo ls > /dev/null
	sudo rm /usr/bin/bmount
	sudo rm -rf /var/bmount
	echo "Config files left in /etc/bmount"
