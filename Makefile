root=/
prefix:=$(root)usr/local
apphome=$(root)usr/local/share/dialup_manager
bindir=$(prefix)/bin
rel_date=1.1.00
rel_version=1.1

files=dialup_manager.pl dialup_manager.sh Dialup_Cost.pm Graphs.pm\
 dialup_cost.data dialup_manager.cfg\
 status_reader.pl locale-de about-de about-en

cfg_src=about-en.in about-de.in

sources=dialup_manager.pl dialup_manager.sh Dialup_Cost.pm Graphs.pm\
 dialup_cost.data dialup_manager.cfg status_reader.pl


targets: about-en about-en tkdialup

all: dist.deb dist.tar.gz

force:

%:%.in force
	sed -f configure.sed >$@ $<

dist/DEBIAN/postinst dist/DEBIAN/control: force
	mkdir -p dist/DEBIAN dist/$(prefix)/bin
	echo "#! /bin/sh" > dist/DEBIAN/postinst
	echo "chmod 04755 $(apphome)/status_reader.pl" >> dist/DEBIAN/postinst
	echo "chown root.root $(apphome)/status_reader.pl" >> dist/DEBIAN/postinst
	chmod 755 dist/DEBIAN/postinst
	install ./packages/debian/control ./dist/DEBIAN/control

tkdialup: tkdialup.in force
	sed -e "s+@APP_HOME@+$(apphome)+g" tkdialup.in >tkdialup && chmod 755 tkdialup

install: force
	install -d $(apphome) $(prefix)/bin
	install $(files) $(apphome)
	install -m 04755 status_reader.pl $(apphome)
	install -m 00755 tkdialup $(bindir)
distclean: force
	rm -rf ./dist

# User Distributions
## Tar Archive
dist.tgz: targets force
	rm -rf ./dist
	$(MAKE) root=./dist/ install
	cd ./dist && tar -vczf ../dist.tgz .
uninstall:
	rm -rf $(apphome)
