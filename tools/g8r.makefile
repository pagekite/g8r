#!/usr/bin/make -f
#
# This is a magic Makefile which will use jinjatool.py to build a static
# website or g8r script tree. It knows how to ask jinjatool.py to calculate
# dependencies and update itself with whatever rules are necessary.
#
JINJATOOL_VARS = g8r
JINJATOOL_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
JINJATOOL := $(abspath $(JINJATOOL_ROOT)/../tools)/jinjatool.py
MP_RFC822 ?= $(shell find . -name template.md-jinja |head -1)

MAKE = make JINJATOOL_ROOT=$(JINJATOOL_ROOT) JINJATOOL_VARS=$(JINJATOOL_VARS) JINJATOOL=$(JINJATOOL) MP_RFC822=$(MP_RFC822) \
            -f $(word 1,$(MAKEFILE_LIST)) --no-print-directory
EXCLUDE = grep -v -e /bin/ -e /canaries/ -e /hosts/ -e /skeletons/ -e /recipes/
MAKE_ONLY ?= cat
TARGETS = find . -name \*.jinja* -o -name \*.md \
            |$(MAKE_ONLY) |$(EXCLUDE) \
            |grep -v -e '.swp$$' -e '.py$$' -e '~$$' -e 'README.md' -e 'PLAN.md' |sort \
            |sed -e 's/md$$/html/g' \
                 -e 's/jinja-txt$$/txt/g' \
                 -e 's/jinja-rss$$/rss/g' \
                 -e 's/jinja-json$$/json/g' \
                 -e 's/jinja-js$$/js/g' \
                 -e 's/jinja-sh$$/sh/g' \
                 -e 's/jinja$$/html/g'


all:
	@find . -name '*.md.py' -mmin +15 |$(EXCLUDE) |xargs touch /dev/null
	@$(TARGETS) |xargs -r $(MAKE)

clean:
	@$(TARGETS) |xargs -r rm -f
	rm -f .depend .depend.up

loop: .depend
	@while [ 1 ]; do \
	  $(TARGETS) |xargs -r $(MAKE) \
            |grep -v 'up to date' \
            || sleep 1; \
         done

%.txt: %.jinja-txt
	LC_ALL=C JINJATOOL_ROOT=$(JINJATOOL_ROOT) JINJATOOL_VARS=$(JINJATOOL_VARS) $(JINJATOOL) $<:$@

%.rss: %.jinja-rss
	LC_ALL=C JINJATOOL_ROOT=$(JINJATOOL_ROOT) JINJATOOL_VARS=$(JINJATOOL_VARS) $(JINJATOOL) $<:$@

%.json: %.jinja-json
	LC_ALL=C JINJATOOL_ROOT=$(JINJATOOL_ROOT) JINJATOOL_VARS=$(JINJATOOL_VARS) $(JINJATOOL) $<:$@

%.js: %.jinja-js
	LC_ALL=C JINJATOOL_ROOT=$(JINJATOOL_ROOT) JINJATOOL_VARS=$(JINJATOOL_VARS) $(JINJATOOL) $<:$@

%.sh: %.jinja-sh
	LC_ALL=C JINJATOOL_ROOT=$(JINJATOOL_ROOT) JINJATOOL_VARS=$(JINJATOOL_VARS) $(JINJATOOL) $<:$@
	chmod +x $@

%.html: %.jinja
	LC_ALL=C JINJATOOL_ROOT=$(JINJATOOL_ROOT) JINJATOOL_VARS=$(JINJATOOL_VARS) $(JINJATOOL) $<:$@

%.html: %.md
	LC_ALL=C JINJATOOL_ROOT=$(JINJATOOL_ROOT) JINJATOOL_VARS=$(JINJATOOL_VARS) \
            $(JINJATOOL) dir="`pwd`" MP_RFC822_FILE="$<" $(MP_RFC822):$@

%.jinja: %.jinja.py
	(cd $(<D); ./$(<F)) > $@

%.jinja:
	@touch $@

%.jinja-rss:
	@touch $@

%.jinja-json:
	@touch $@

%.jinja-js:
	@touch $@

%.jinja-sh:
	@touch $@

%.md: %.md.py
	(cd $(<D); ./$(<F)) > $@

%.md:
	@touch $@

%.md-jinja:
	@touch $@

%.html-jinja:
	@touch $@

.depend.up:
	touch .depend.up

.depend: Makefile .depend.up recipes skeletons
	find . -type f \
          |grep -e /bin/ -e '.jinja' -e '.py$$' -e '.vars$$' -e '.yml$$' \
          |$(MAKE_ONLY) \
          |xargs chmod go-rwx
	(export M=$(MP_RFC822); \
         export JINJATOOL_ROOT=$(JINJATOOL_ROOT); \
         export JINJATOOL_VARS=$(JINJATOOL_VARS); \
         $(JINJATOOL) --deps \
            `find . -name \*.jinja\* |$(EXCLUDE) |grep -v .swp |sort` \
            `find . -name \*.md -printf "MP_RFC822_FILE=%p $$M:%p\\n" |sort` \
        ) |$(EXCLUDE) >.depend

include .depend
