# GNU make file
#
root=/
prefix:=$(root)usr/local
apphome=$(root)usr/local/share/dialup_manager
bindir=$(prefix)/bin
docdir=$(apphome)

appfiles=dialup_manager.pl dialup_manager.sh Dialup_Cost.pm Graphs.pm\
 dialup_cost.data dialup_manager.cfg\
 status_reader.pl locale-de about-de about-en\
 stat_new.pl stat_new.sh

cfg_src=about-en.in about-de.in
examplefiles=dialup_manager.cfg dialup_cost.data
docfiles=README.de README INSTALL.de INSTALL ChangeLog

sources=dialup_manager.pl dialup_manager.sh Dialup_Cost.pm Graphs.pm\
 status_reader.pl about-en.in about-de.in tkdialup.in \
 Makefile Makefile-deb configure.sed\
 about-en.in about-de.in locale-de \
 dialup_manager.cfg dialup_cost.data\
 README.de README INSTALL.de INSTALL ChangeLog\
 stat_new.pl stat_new.sh

targets=about-en about-de tkdialup
opt_targets=dist.tgz

all: $(targets)

force:

%:%.in force
	sed -f configure.sed >$@ $<

tkdialup: tkdialup.in force
	sed -e "s+@APP_HOME@+$(apphome)+g" tkdialup.in >tkdialup && chmod 755 tkdialup

rcs_init: force
	ci -i -t/dev/null $(sources) 

install: force
	install -d $(apphome) $(prefix)/bin
	install $(appfiles) $(apphome)
	install -m 00644 $(docfiles) $(docdir)
	install -m 04755 status_reader.pl $(apphome)
	install -m 00755 tkdialup $(bindir)

clean: force
	rm -f $(targets) $(opt_targets)

# User Distributions
## generic
dist.tgz: targets force
	rm -rf ./dist
	$(MAKE) root=./dist/ install
	cd ./dist && tar -vczf ../dist.tgz .
dist.deb: force
	fakeroot $(MAKE) -f ./Makefile-deb dist.deb
uninstall:
	rm -rf $(apphome)
	rm $(bindir)/tkdialup
# Src Distribitions
src.tar.gz: $(sources)
	tar -czf src.tar.gz $(sources)
