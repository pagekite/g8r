default:
	@./g8r make

shellcheck:
	shellcheck g8r tools/*.sh

shfmt:
	shfmt -i 2 -ci -bn g8r tools/*.sh
