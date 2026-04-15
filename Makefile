default:
	@echo "Try 'make rebuild' or 'make check' ..."

rebuild:
	@./g8r make

check: codeclean checktree

checktree: rebuild
	find tree -type f -name \*.sh |xargs shellcheck

codeclean: shfmt shellcheck
	@true

shellcheck:
	shellcheck g8r tools/*.sh

shfmt:
	shfmt -w -i 4 -ci -bn g8r tools/*.sh
