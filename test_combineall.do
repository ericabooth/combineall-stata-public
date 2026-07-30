* test_combineall.do -- test battery for combineall v2.0.1
* Run from any scratch directory:  stata-mp -b do test_combineall.do
* All paths live in globals set here; nothing below is hard-coded.

clear all
set more off
set seed 20260706

* ------------------------------------------------------------------ *
* Globals (edit these two lines only when the package moves)          *
* ------------------------------------------------------------------ *
global pkgroot "/Users/ebooth/Documents/GitHub/Book Manuscript:Applied Evaluation-Stata/combineall-stata-public"
global T "`c(tmpdir)'/combineall_test"

* ++ prepends: the packaged v2.0.0 must shadow any older combineall
* (e.g., a 2011 copy in the PERSONAL ado path)
adopath ++ "$pkgroot"
which combineall

* ------------------------------------------------------------------ *
* 0. Build a clean scratch tree under the system tempdir              *
* ------------------------------------------------------------------ *
capture mkdir "$T"
foreach sub in conv dtaapp data pos mrg out bad tok tok2 ts {
    capture mkdir "$T/`sub'"
    local stale : dir "$T/`sub'" files "*"
    foreach f of local stale {
        erase "$T/`sub'/`f'"
    }
}
local stale : dir "$T" files "*"
foreach f of local stale {
    erase "$T/`f'"
}

* ------------------------------------------------------------------ *
* 1. convertonly: a tempdir of generated CSVs becomes .dta copies     *
* ------------------------------------------------------------------ *
forvalues k = 1/3 {
    clear
    set obs 4
    gen int id       = _n
    gen double v`k'  = _n * `k'
    export delimited using "$T/conv/c`k'.csv", replace
}

combineall, cmethod(convertonly) directory("$T/conv") prefix(z)
assert r(n_files) == 3
forvalues k = 1/3 {
    confirm file "$T/conv/zc`k'.dta"
}
use "$T/conv/zc2.dta", clear
assert _N == 4
confirm variable id v2
quietly summarize v2
assert r(mean) == 5                    // (2+4+6+8)/4

* ------------------------------------------------------------------ *
* 2. append of generated .dta files, with fileid()                    *
* ------------------------------------------------------------------ *
clear
set obs 5
gen int id    = _n
gen double a  = 10 * _n
quietly save "$T/dtaapp/f1.dta"

clear
set obs 3
gen int id    = _n + 5
gen double a  = 100 * _n
quietly save "$T/dtaapp/f2.dta"

combineall using "$T/out/append1", cmethod(append) ///
    directory("$T/dtaapp") filetype(dta) fileid(srcfile)
assert r(n_files) == 2
use "$T/out/append1.dta", clear
assert _N == 8
confirm variable id a srcfile
quietly count if srcfile == "f1.dta"
assert r(N) == 5
quietly count if srcfile == "f2.dta"
assert r(N) == 3
quietly summarize a if srcfile == "f2.dta" & id == 8
assert r(mean) == 300                  // 100 * 3

* ------------------------------------------------------------------ *
* 3. clobber/replace guard: rerun without replace errors (198),       *
*    rerun with replace succeeds                                      *
* ------------------------------------------------------------------ *
capture noisily combineall using "$T/out/append1", cmethod(append) ///
    directory("$T/dtaapp") filetype(dta)
assert _rc == 198

combineall using "$T/out/append1", cmethod(append) ///
    directory("$T/dtaapp") filetype(dta) replace
use "$T/out/append1.dta", clear
assert _N == 8

* ------------------------------------------------------------------ *
* 4. append with map(): the panelstack vintage-rename test            *
*    enroll_cnt (2019-2020) becomes enrollment in 2021;               *
*    mscore (2019 only) becomes mathscore in 2020;                    *
*    attend_rate exists in 2020 only but its map window is 2020-2021, *
*    so 2021 must produce a report (and an error under strict).       *
* ------------------------------------------------------------------ *
* 2019: 5 campuses
clear
set obs 5
gen int campus     = _n
gen int enroll_cnt = 100 * campus
gen double mscore  = 50 + campus
export delimited using "$T/data/enr_2019.csv", replace

* 2020: 6 campuses
clear
set obs 6
gen int campus         = _n
gen int enroll_cnt     = 200 * campus
gen double mathscore   = 60 + campus
gen double attend_rate = 0.90 + campus/100
export delimited using "$T/data/enr_2020.csv", replace

* 2021: 7 campuses, already uses the final names
clear
set obs 7
gen int campus       = _n
gen int enrollment   = 300 * campus
gen double mathscore = 70 + campus
export delimited using "$T/data/enr_2021.csv", replace

* the rename map (blank firstyear/lastyear = open-ended);
* kept OUTSIDE $T/data so it is not swept up as an input file
tempname m
file open `m' using "$T/map.csv", write replace
file write `m' "oldname,newname,firstyear,lastyear" _n
file write `m' "enroll_cnt,enrollment,,2020" _n
file write `m' "mscore,mathscore,2019,2019" _n
file write `m' "attend_rate,attendance,2020,2021" _n
file close `m'

combineall using "$T/out/panel", cmethod(append) ///
    directory("$T/data") map("$T/map.csv")
local nf   = r(n_files)
local nv   = r(n_vars)
local nmis = r(n_missing)
local yrs  "`r(years)'"

assert `nf' == 3
assert `nv' == 5                       // year campus enrollment mathscore attendance
assert `nmis' == 1                     // attend_rate absent from 2021 file
assert "`yrs'" == "2019 2020 2021"

use "$T/out/panel.dta", clear
assert _N == 18                        // 5 + 6 + 7

* year variable: stamped, int, correct per-file counts
confirm variable year
assert "`: type year'" == "int"
quietly count if year == 2019
assert r(N) == 5
quietly count if year == 2020
assert r(N) == 6
quietly count if year == 2021
assert r(N) == 7

* harmonized names: new names exist, old names are gone
confirm variable campus enrollment mathscore attendance
capture confirm variable enroll_cnt
assert _rc == 111
capture confirm variable mscore
assert _rc == 111
capture confirm variable attend_rate
assert _rc == 111

* predict-then-check values straight from the generating formulas
assert !missing(enrollment)
quietly summarize enrollment if year == 2019 & campus == 3
assert r(mean) == 300                  // 100 * 3
quietly summarize enrollment if year == 2020 & campus == 6
assert r(mean) == 1200                 // 200 * 6
quietly summarize enrollment if year == 2021 & campus == 7
assert r(mean) == 2100                 // 300 * 7
quietly summarize mathscore if year == 2019 & campus == 1
assert r(mean) == 51                   // 50 + 1
quietly count if !missing(attendance)
assert r(N) == 6                       // 2020 rows only
quietly count if !missing(attendance) & year != 2020
assert r(N) == 0

* provenance chars (saved into the output .dta)
local src : char enrollment[source]
assert strpos(`"`src'"', "enroll_cnt (enr_2019.csv, 2019)") > 0
assert strpos(`"`src'"', "enroll_cnt (enr_2020.csv, 2020)") > 0
local src : char mathscore[source]
assert `"`src'"' == "mscore (enr_2019.csv, 2019)"
local src : char attendance[source]
assert `"`src'"' == "attend_rate (enr_2020.csv, 2020)"

* ------------------------------------------------------------------ *
* 5. year() as a position spec and as a custom regex                  *
*    Default regex would grab 2020 first; position 14 reads 2019.     *
* ------------------------------------------------------------------ *
clear
set obs 4
gen int campus     = _n
gen int enroll_cnt = 10 * campus
export delimited using "$T/pos/batch2020run_2019.csv", replace

combineall using "$T/out/pos", cmethod(append) ///
    directory("$T/pos") map("$T/map.csv") year(14)
assert r(n_files) == 1
assert "`r(years)'" == "2019"
use "$T/out/pos.dta", clear
assert _N == 4
confirm variable enrollment            // 2019 is inside the map window

combineall using "$T/out/pos", cmethod(append) directory("$T/pos") ///
    map("$T/map.csv") year("run_([0-9][0-9][0-9][0-9])") replace
assert "`r(years)'" == "2019"

* ------------------------------------------------------------------ *
* 6. merge path on two generated files with mvars() and _merge        *
*    (merge keys must be strings: the seed master creates them so)    *
* ------------------------------------------------------------------ *
clear
set obs 4
gen str5 code = "k" + string(_n)
gen double x1 = _n
quietly save "$T/mrg/m1.dta"

clear
set obs 4
gen str5 code = "k" + string(_n)
gen double x2 = 10 * _n
quietly save "$T/mrg/m2.dta"

combineall using "$T/out/merged", cmethod(merge) ///
    directory("$T/mrg") filetype(dta) mvars(code) _merge
assert r(n_files) == 2
use "$T/out/merged.dta", clear
assert _N == 4
confirm variable code x1 x2 _m1 _m2
assert x2 == 10 * x1
assert _m1 == 2                        // rows arrived from m1.dta
assert _m2 == 3                        // and matched m2.dta

* ------------------------------------------------------------------ *
* 7. Deliberate error cases                                           *
* ------------------------------------------------------------------ *
* 7a. strict: attend_rate absent from the 2021 CSV -> r(111)
capture noisily combineall using "$T/out/strictout", cmethod(append) ///
    directory("$T/data") map("$T/map.csv") strict
assert _rc == 111
capture erase "$T/out/strictout.dta"   // partial output from the aborted run

* 7b. harmonization options require cmethod(append) -> r(198)
capture noisily combineall using "$T/out/badgraft", cmethod(merge) ///
    directory("$T/mrg") filetype(dta) mvars(code) map("$T/map.csv")
assert _rc == 198

* 7c. year()/strict without map() -> r(198)
capture noisily combineall using "$T/out/badgraft2", cmethod(append) ///
    directory("$T/data") year(14)
assert _rc == 198

* 7d. no files of the requested type -> r(601)
capture noisily combineall using "$T/out/none", cmethod(append) ///
    directory("$T/bad")
assert _rc == 601

* ------------------------------------------------------------------ *
* 8. File-list construction: the output stem and the file extension   *
*    are matched as WHOLE tokens, never stripped as substrings.       *
* ------------------------------------------------------------------ *
* 8a. Output stem "my" excludes my.csv only.  The pre-v2.0.1 engine
*     ran subinstr over the whole file list, so mydata.csv silently
*     became data.csv: the wrong file was read, with rc 0 and no warning.
clear
set obs 2
gen int id  = _n
gen str12 who = "my"
export delimited using "$T/tok/my.csv", replace

clear
set obs 3
gen int id  = _n
gen str12 who = "mydata"
export delimited using "$T/tok/mydata.csv", replace

combineall using "$T/tok/my", cmethod(append) ///
    directory("$T/tok") fileid(srcfile) replace
assert r(n_files) == 1                 // my.csv is the output, mydata.csv is not
use "$T/tok/my.dta", clear
assert _N == 3                         // mydata.csv only
levelsof srcfile, local(sf) clean
assert "`sf'" == "mydata.csv"
levelsof who, local(wh) clean
assert "`wh'" == "mydata"

* 8b. The extension string appearing INSIDE a filename must survive:
*     mycsvdata.csv and my.csvdata.csv are distinct inputs under
*     filetype(csv), and only the trailing ".csv" is stripped.
clear
set obs 2
gen int id  = _n
gen str12 who = "mycsvdata"
export delimited using "$T/tok2/mycsvdata.csv", replace

clear
set obs 3
gen int id  = _n
gen str12 who = "dotcsvdata"
export delimited using "$T/tok2/my.csvdata.csv", replace

combineall using "$T/out/tok2out", cmethod(append) ///
    directory("$T/tok2") fileid(srcfile) replace
assert r(n_files) == 2
use "$T/out/tok2out.dta", clear
assert _N == 5                         // 2 + 3
levelsof srcfile, local(sf) clean
assert "`sf'" == "my.csvdata.csv mycsvdata.csv"
levelsof who, local(wh) clean
assert "`wh'" == "dotcsvdata mycsvdata"

* ------------------------------------------------------------------ *
* 9. tostring uses the display format, and so is lossy for numerics.  *
*    A double holding 1/3 under %10.0g becomes the string ".33333333";*
*    the help documents this under the tostring option.               *
* ------------------------------------------------------------------ *
clear
set obs 3
gen double third = _n/3
export delimited using "$T/ts/nums.csv", replace

combineall, cmethod(convertonly) directory("$T/ts") prefix(t) tostring
assert r(n_files) == 1
use "$T/ts/tnums.dta", clear
assert substr("`: type third'", 1, 3) == "str"
assert third[1] == ".33333333"         // not 1/3 to full double precision
assert third[2] == ".66666667"

* ------------------------------------------------------------------ *
* 10. A bare combineall (no comma, no options) is legal: convertonly  *
*     over the .csv files in the working directory.  The syntax       *
*     diagram in the help shows the comma inside the brackets.        *
* ------------------------------------------------------------------ *
local cwd "`c(pwd)'"
cd "$T/conv"
combineall
assert r(n_files) == 3
confirm file "c1.dta"
confirm file "c3.dta"
cd "`cwd'"

* ------------------------------------------------------------------ *
* 11. Clean up the scratch tree                                       *
* ------------------------------------------------------------------ *
clear
foreach sub in conv dtaapp data pos mrg out bad tok tok2 ts {
    local stale : dir "$T/`sub'" files "*"
    foreach f of local stale {
        erase "$T/`sub'/`f'"
    }
    rmdir "$T/`sub'"
}
local stale : dir "$T" files "*"
foreach f of local stale {
    erase "$T/`f'"
}
rmdir "$T"

di as txt _n "test_combineall.do: all asserts passed"
