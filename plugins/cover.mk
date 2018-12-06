# Copyright (c) 2016, Loïc Hoguin <essen@ninenines.eu>
# Copyright (c) 2015, Viktor Söderqvist <viktor@zuiderkwast.se>
# This file is part of erlang.mk and subject to the terms of the ISC License.

COVER_REPORT_DIR ?= cover
COVER_DATA_DIR ?= $(COVER_REPORT_DIR)

# Code coverage for Common Test.

ifdef COVER
ifdef CT_RUN
ifneq ($(wildcard $(TEST_DIR)),)
test-build:: $(TEST_DIR)/ct.cover.spec

$(TEST_DIR)/ct.cover.spec: cover-data-dir
	$(gen_verbose) printf "%s\n" \
		"{incl_app, '$(PROJECT)', details}." \
		'{export,"$(abspath $(COVER_DATA_DIR))/ct.coverdata"}.' > $@

CT_RUN += -cover $(TEST_DIR)/ct.cover.spec
endif
endif
endif

# Code coverage for other tools.

ifdef COVER
define cover.erl
	CoverSetup = fun() ->
		case filelib:is_dir("ebin") of
			false -> false;
			true ->
				case cover:compile_beam_directory("ebin") of
					{error, _} -> halt(1);
					_ -> true
				end
		end
	end,
	CoverExport = fun(Filename) -> cover:export(Filename) end,
endef
else
define cover.erl
	CoverSetup = fun() -> ok end,
	CoverExport = fun(_) -> ok end,
endef
endif

# Core targets

ifdef COVER
ifneq ($(COVER_REPORT_DIR),)
tests::
	$(verbose) $(MAKE) --no-print-directory cover-report
endif

cover-data-dir: | $(COVER_DATA_DIR)

$(COVER_DATA_DIR):
	$(verbose) mkdir -p $(COVER_DATA_DIR)
else
cover-data-dir:
endif

clean:: coverdata-clean

ifneq ($(COVER_REPORT_DIR),)
distclean:: cover-report-clean
endif

help::
	$(verbose) printf "%s\n" "" \
		"Cover targets:" \
		"  cover-report  Generate a HTML coverage report from previously collected" \
		"                cover data." \
		"  all.coverdata Merge all coverdata files into all.coverdata." \
		"" \
		"If COVER=1 is set, coverage data is generated by the targets eunit and ct. The" \
		"target tests additionally generates a HTML coverage report from the combined" \
		"coverdata files from each of these testing tools. HTML reports can be disabled" \
		"by setting COVER_REPORT_DIR to empty."

# Plugin specific targets

COVERDATA = $(filter-out $(COVER_DATA_DIR)/all.coverdata,$(wildcard $(COVER_DATA_DIR)/*.coverdata))

.PHONY: coverdata-clean
coverdata-clean:
	$(gen_verbose) rm -f $(COVER_DATA_DIR)/*.coverdata $(TEST_DIR)/ct.cover.spec

# Merge all coverdata files into one.
define cover_export.erl
	$(foreach f,$(COVERDATA),cover:import("$(f)") == ok orelse halt(1),)
	cover:export("$(COVER_DATA_DIR)/$@"), halt(0).
endef

all.coverdata: $(COVERDATA) cover-data-dir
	$(gen_verbose) $(call erlang,$(cover_export.erl))

# These are only defined if COVER_REPORT_DIR is non-empty. Set COVER_REPORT_DIR to
# empty if you want the coverdata files but not the HTML report.
ifneq ($(COVER_REPORT_DIR),)

.PHONY: cover-report-clean cover-report

cover-report-clean:
	$(gen_verbose) rm -rf $(COVER_REPORT_DIR)
	$(if $(shell ls -A $(COVER_DATA_DIR)/),,$(verbose) rmdir $(COVER_DATA_DIR))

ifeq ($(COVERDATA),)
cover-report:
else

# Modules which include eunit.hrl always contain one line without coverage
# because eunit defines test/0 which is never called. We compensate for this.
EUNIT_HRL_MODS = $(subst $(space),$(comma),$(shell \
	grep -H -e '^\s*-include.*include/eunit\.hrl"' src/*.erl \
	| sed "s/^src\/\(.*\)\.erl:.*/'\1'/" | uniq))

define cover_report.erl
	$(foreach f,$(COVERDATA),cover:import("$(f)") == ok orelse halt(1),)
	Ms = cover:imported_modules(),
	[cover:analyse_to_file(M, "$(COVER_REPORT_DIR)/" ++ atom_to_list(M)
		++ ".COVER.html", [html])  || M <- Ms],
	Report = [begin {ok, R} = cover:analyse(M, module), R end || M <- Ms],
	EunitHrlMods = [$(EUNIT_HRL_MODS)],
	Report1 = [{M, {Y, case lists:member(M, EunitHrlMods) of
		true -> N - 1; false -> N end}} || {M, {Y, N}} <- Report],
	TotalY = lists:sum([Y || {_, {Y, _}} <- Report1]),
	TotalN = lists:sum([N || {_, {_, N}} <- Report1]),
	Perc = fun(Y, N) -> case Y + N of 0 -> 100; S -> round(100 * Y / S) end end,
	TotalPerc = Perc(TotalY, TotalN),
	{ok, F} = file:open("$(COVER_REPORT_DIR)/index.html", [write]),
	io:format(F, "<!DOCTYPE html><html>~n"
		"<head><meta charset=\"UTF-8\">~n"
		"<title>Coverage report</title></head>~n"
		"<body>~n", []),
	io:format(F, "<h1>Coverage</h1>~n<p>Total: ~p%</p>~n", [TotalPerc]),
	io:format(F, "<table><tr><th>Module</th><th>Coverage</th></tr>~n", []),
	[io:format(F, "<tr><td><a href=\"~p.COVER.html\">~p</a></td>"
		"<td>~p%</td></tr>~n",
		[M, M, Perc(Y, N)]) || {M, {Y, N}} <- Report1],
	How = "$(subst $(space),$(comma)$(space),$(basename $(COVERDATA)))",
	Date = "$(shell date -u "+%Y-%m-%dT%H:%M:%SZ")",
	io:format(F, "</table>~n"
		"<p>Generated using ~s and erlang.mk on ~s.</p>~n"
		"</body></html>", [How, Date]),
	halt().
endef

cover-report:
	$(verbose) mkdir -p $(COVER_REPORT_DIR)
	$(gen_verbose) $(call erlang,$(cover_report.erl))

endif
endif # ifneq ($(COVER_REPORT_DIR),)
