# GNU+BSD (?) make file
## $Id: Makefile,v 1.3 2000/08/30 22:50:37 bertw Exp bertw $

root=/
prefix:=$(root)usr/local
apphome=$(root)usr/local/share/tkdialup
bindir=$(prefix)/bin
docdir=$(apphome)

# all sourcefiles
sources = Utils.pm Pon.pm dm.pm dmsock.pm tkdialup.pl tkdialup.sh Dialup_Cost.pm Graphs.pm\
 status_reader.pl about-en.in about-de.in tkdialup.in\
 Makefile Makefile-deb Makefile-wine configure.sh\
 about-en.in about-de.in language-de country-DE\
 dialup_manager.cfg dialup_cost.data\
 LOCALE README-de README INSTALL-de INSTALL ChangeLog COPYRIGHT BUGS TODO README-w32-de.html\
 stat_new.pl stat_new.sh log_stat.pm\
 packages/debian/control\
 w32ras_dialer.c w32ras_dialer2.c w32phonebook.txt\
 TkDialup.chat TkDialup-pppd

# file classes
share_appfiles = Utils.pm Pon.pm dm.pm dmsock.pm tkdialup.pl tkdialup.sh Dialup_Cost.pm Graphs.pm\
 dialup_cost.data dialup_manager.cfg\
 language-de country-DE language-skl country-SKL about-de about-en\
 stat_new.pl stat_new.sh log_stat.pm COPYRIGHT
appfiles =$(share_appfiles)  status_reader.pl TkDialup.chat w32phonebook.txt
cfg_src = about-en.in about-de.in
examplefiles = dialup_manager.cfg dialup_cost.data
share_docfiles = LOCALE README-de README INSTALL-de INSTALL ChangeLog COPYRIGHT BUGS TODO  README-w32-de.html
docfiles = $(share_docfiles)
comm_targets=about-en about-de tkdialup
targets=$(comm_targets)

opt_targets=dist.tar.gz src.tar.gz w32dist.zip

## files fed to etags
tag_src = Utils.pm Pon.pm dm.pm dmsock.pm tkdialup.pl Dialup_Cost.pm Graphs.pm

all: $(targets)

force:

about-de: about-de.in force
	configure.sh about-de.in >about-de && touch -r about-de.in about-de
about-en: about-en.in force
	configure.sh about-en.in >about-en && touch -r  about-en.in about-en
tkdialup: tkdialup.in force
	sed -e "s+@APP_HOME@+$(apphome)+g" tkdialup.in >tkdialup && chmod 755 tkdialup
#%:%.in configure.sh  revision.stamp
#	configure.sh >$@ $<

language-skl: language-de Makefile
	sed -e 's/^\([^=]*=\).*$$/\1/' -e '/^#.*$$/d' language-de >language-skl

country-SKL: country-DE Makefile
	sed -e 's/^\([^=]*=\).*$$/\1/' -e '/^#.*$$/d' country-DE >country-SKL

rcs_init: force
	ci -i -t/dev/null $(sources) 
rcs_co: $(sources)

install: force
	install -d $(apphome) $(prefix)/bin $(docdir)
	install -m 00644 $(appfiles) $(apphome)
	install -m 00644 $(docfiles) $(docdir)
	install -m 04755 status_reader.pl $(apphome)
	install -m 00755 tkdialup.sh tkdialup.pl $(apphome)
	install -m 00755 tkdialup $(bindir)

clean: force
	rm -f $(targets) $(opt_targets)

TAGS: $(tag_src)
	etags $(tag_src)

# restore permissions
fix_perm: force
	chmod 644 *.c $(docfiles) *.pm Makefile* *~ *.in

bump_revision: force
	rm -f $(revision_targets)
	$(MAKE) $(revision_targets)

# User Distributions
## generic
dist.tgz: $(targets) $(docfiles)
	rm -rf ./dist
	$(MAKE) root=./dist/ install
	cd ./dist && tar -vczf ../dist.tgz .
dist.deb: force $(sources)
	if [ $$(id -u) != 0  ]; then fakeroot $(MAKE) -f ./Makefile-deb dist.deb;\
 else $(MAKE) -f ./Makefile-deb dist.deb; fi
uninstall:
	rm -rf $(apphome)
	rm $(bindir)/tkdialup
# Src Distribitions
# prefixed with AppName-Version directory
src.tar.gz: $(sources)
	name=$$(echo @APP_NAME@-@APP_VERSION@ | configure.sh);\
 rm -rf tmp/$$name; mkdir -p tmp/$$name &&\
 tar -cf- $(sources) | tar -xf- -C tmp/$$name &&\
 (cd tmp && tar -czf ../src.tar.gz $$name) &&\
 rm -rf tmp/$$name
dist.tar.gz: $(sources)
	$(MAKE) $(targets)
	name=$$(echo @APP_NAME@-@APP_VERSION@ | configure.sh);\
 rm -rf tmp/$$name; mkdir -p tmp/$$name &&\
 tar -cf- $(sources) $(targets) | tar -xf- -C tmp/$$name &&\
 (cd tmp && tar -czf ../dist.tar.gz $$name) && rm -rf tmp/$$name


### W32 ###

w32_appfiles_bin = w32ras_dialer.exe w32ras_dialer2.exe
w32_appfiles = $(share_appfiles) w32ras_dialer.c w32ras_dialer2.c w32phonebook.txt
w32_docfiles = $(share_docfiles)
# w32 distribution is in a single directory.
w32_distfiles_txt = $(w32_appfiles) $(w32_docfiles) $(docfiles)
w32_distfiles_bin = $(w32_appfiles_bin)
w32_distfiles = $(w32_distfiles_txt) $(w32_appfiles_bin) 
w32_targets = $(comm_targets) w32ras_dialer.exe w32ras_dialer2.exe

w32dist.zip: $(w32_distfiles) Makefile
	$(MAKE) $(targets)
	rm -f w32dist.zip
	(name=$$(echo @APP_NAME@-@APP_VERSION@ | configure.sh) &&\
 rm -rf tmp/$$name && mkdir -p tmp/$$name &&\
   tar -cf- $(w32_distfiles_txt) | tar -xf- -C tmp/$$name &&\
   (cd tmp/$$name &&\
       mv LOCALE LOCALE.txt &&\
       mv README-de README-de.txt &&\
       mv README README.txt &&\
       mv INSTALL INSTALL.txt &&\
       mv INSTALL-de INSTALL-de.txt &&\
       mv BUGS BUGS.txt &&\
       mv TODO TODO.txt &&\
       mv README-w32-de.html README-w32-de.htm &&\
       cp COPYRIGHT COPYRIGHT.txt &&\
       sed -e 's/&pppd /\&w32ras /g' -e 's/\<pon\>/\&w32ras/' -e 's/\<poff\>/\&w32ras/' dialup_manager.cfg  >tem &&\
           rm -f dialup_manager.cfg  && mv tem dialup_manager.cfg) &&\
   (cd tmp/$$name && zip -lr ../../w32dist.zip *) &&\
 rm -rf tmp/$$name &&  mkdir -p tmp/$$name &&\
   tar -cf- $(w32_distfiles_bin) | tar -xf- -C tmp/$$name &&\
   (cd tmp/$$name && zip -r ../../w32dist.zip *) &&\
 rm -rf tmp/$$name)  || (rm w32dist.zip && false)

### Make Windows-Setup binary on Unix by running native Setup_Generator with Wine ###
w32dist.exe: w32dist.zip
	$(MAKE) -f Makefile-wine w32dist.exe

### Compiling Windows binary on Unix using native lcc32win with Wine ###
w32ras_dialer.exe: w32ras_dialer.c
	$(MAKE) -f Makefile-wine w32ras_dialer.exe \
 "w32_rd_ldflags=-subsystem console" "w32_rd_libs=tcconio.lib rasapi32.lib"

w32ras_dialer2.exe: w32ras_dialer2.c
	$(MAKE) -f Makefile-wine w32ras_dialer2.exe \
 "w32_rd_ldflags=-subsystem windows" "w32_rd_libs=rasapi32.lib wsock32.lib"

db_w32ras_dialer2.exe: force
	rm -f w32ras_dialer2.exe
	$(MAKE) -f Makefile-wine w32ras_dialer2.exe \
 "w32_rd_ldflags=-subsystem console" "w32_rd_libs=tcconio.lib rasapi32.lib wsock32.lib "
	touch -t 199901010000  w32ras_dialer2.exe

### Compiling windows binary on Windows using lcc32win ###
# lcc32win-Make

w32_CC=C:\lcc\bin\lcc.exe
w32_CPPFLAGS=-IC:\lcc\include
w32_LD=C:\lcc\bin\lcclnk.exe

w32_rd_libs=tcconio.lib rasapi32.lib
w32_rd_ldflags=-subsystem console


W32ras_dialer.exe: w32ras_dialer.c
	$(w32_CC) -c $(w32_CPPFLAGS) w32ras_dialer.c #-o w32ras_dialer.obj
	$(w32_LD)  $(w32_rd_ldflags) -o w32ras_dialer.exe  w32ras_dialer.obj $(w32_rd_libs)

w32_rd2db_libs=tcconio.lib rasapi32.lib wsock32.lib
w32_rd2db_ldflags=-subsystem console
db_W32ras_dialer2.exe: w32ras_dialer2.c Makefile
	$(w32_CC) -c $(w32_CPPFLAGS) w32ras_dialer2.c #-o w32ras_dialer.obj
	$(w32_LD)  $(w32_rd2db_ldflags) -o w32ras_dialer2.exe  w32ras_dialer2.obj $(w32_rd2db_libs)

w32_rd2_libs=rasapi32.lib  wsock32.lib
w32_rd2_ldflags=-subsystem windows
W32ras_dialer2.exe: w32ras_dialer2.c
	$(w32_CC) -c $(w32_CPPFLAGS) w32ras_dialer2.c #-o w32ras_dialer.obj
	$(w32_LD)  $(w32_rd2_ldflags) -o w32ras_dialer2.exe  w32ras_dialer2.obj $(w32_rd2_libs)
