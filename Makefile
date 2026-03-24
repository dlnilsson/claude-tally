R_LIBS_USER ?= $(HOME)/R/library

.PHONY: r-deps graphs clean

r-deps:
	@mkdir -p $(R_LIBS_USER)
	R_LIBS_USER=$(R_LIBS_USER) Rscript -e 'install.packages(c("DBI", "RSQLite", "ggplot2", "dplyr", "lubridate", "scales", "tidyr", "forcats", "patchwork"), repos="https://cloud.r-project.org", quiet=TRUE)'

graphs: r-deps
	@mkdir -p reports
	R_LIBS_USER=$(R_LIBS_USER) Rscript graphs.R --output-dir ./reports

clean:
	rm -rf reports/
