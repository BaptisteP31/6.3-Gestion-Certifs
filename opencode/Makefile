PDFLATEX ?= pdflatex
LATEXMK ?= latexmk

.PHONY: pdf clean

pdf:
	@if command -v $(LATEXMK) >/dev/null 2>&1; then \
		$(LATEXMK) -pdf main.tex; \
	else \
		$(PDFLATEX) main.tex && $(PDFLATEX) main.tex; \
	fi

clean:
	@rm -f main.aux main.fdb_latexmk main.fls main.log main.out main.toc main.pdf
