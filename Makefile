default:
	@./g8r make

codeclean: shfmt shellcheck
	@true

shellcheck:
	shellcheck g8r tools/*.sh

shfmt:
	shfmt -w -i 4 -ci -bn g8r tools/*.sh
