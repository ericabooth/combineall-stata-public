# combineall — combine or convert every file in a directory

**A 2011 directory-combining engine with a 2026 harmonization layer: append, merge, joinby, or convert every file in a folder, and stack yearly vintages under a rename map.**

```stata
combineall using "built/panel", cmethod(append) directory("raw/") map("renames.csv")
```

## The story

`combineall` v1.0.0 shipped in April 2011 as a workhorse for a common chore: a folder full of files that all need to become one dataset. It converts text files (CSV and other delimited formats), Excel, and XML to `.dta`, then combines everything by `append`, `merge`, or `joinby`, or just converts and stops (`convertonly`). Options cover the practical details: a `fileid()` variable recording each row's source file, `_merge` match-status variables per file, `prefix()`/`suffix()` naming for converted copies, `tostring` for type-wobbly sources, and a `replace` guard so an existing output is never silently overwritten.

v2.0.0 (2026) keeps that engine and its option set, raises the floor to Stata 16, replaces the deprecated `insheet` with `import delimited` (and reads Excel properly with `import excel`), and grafts on the harmonization layer developed for the authors' applied-evaluation book. The problem it solves: agencies publish one file per year, and element names mutate across vintages. A column called one thing in 2015 is renamed by 2020, so a naive append stacks unrelated variables. With `map()`, `combineall` extracts the 4-digit year stamped in each filename, sorts the files by year, applies only the renames whose `[firstyear,lastyear]` window covers that year, generates `int year`, and appends everything into one harmonized panel.

Every rename is written down twice. The map CSV is the human-readable record of the harmonization decisions, and each renamed variable carries a characteristic, `char varname[source]`, recording the original name, source file, and year, so the panel documents its own provenance. After stacking, `combineall` prints a harmonization table (each final variable by the years in which it has data) and lists any file where a mapped `oldname` was expected but absent. That absence is a report, not an error, unless you ask for `strict`.

## Install

From GitHub:

```stata
net install combineall, from("https://raw.githubusercontent.com/ericabooth/combineall-stata-public/main/") replace force
help combineall
```

## Quick start

Both blocks below are self-contained and run as shown in an empty working directory. Stata does not create output folders on demand, so each block creates the folders it writes into first; `capture` lets a block be re-run after its folders exist.

The engine, without the layer — append every `.dta` file in a folder, tagging each row with its source:

```stata
capture mkdir "pieces"
capture mkdir "built"

sysuse auto, clear
keep make price mpg
save "pieces/part1.dta", replace
save "pieces/part2.dta", replace

combineall using "built/all.dta", cmethod(append) directory("pieces/") filetype(dta) fileid(srcfile) replace
```

Note that `filetype(dta)` with no `prefix()`/`suffix()` rewrites the sources in place, so this block leaves `srcfile` behind in `pieces/part1.dta` and `pieces/part2.dta`. Point a later command at a fresh folder rather than at `pieces/`.

The layer — build two tiny yearly files whose price column changes name, write a two-line map, and stack:

```stata
capture mkdir "raw"
capture mkdir "built"

sysuse auto, clear
keep make price mpg
export delimited using "raw/cars_2019.csv", replace
rename price price_usd
export delimited using "raw/cars_2020.csv", replace

file open m using "map.csv", write replace
file write m "oldname,newname,firstyear,lastyear" _n
file write m "price_usd,price,2020," _n
file close m

combineall using "built/cars_panel", cmethod(append) directory("raw/") map("map.csv") replace
use "built/cars_panel.dta", clear
char list price[source]
tabulate year
```

The map row reads: from 2020 onward (`firstyear` 2020, `lastyear` blank and so open-ended), `price_usd` is what `price` is called, so fold it back. The stacked panel has one `price` column across both years, and `char list price[source]` shows where the renamed values came from.

## Engine options (2011)

| Option | What it does |
|---|---|
| `cmethod(method)` | `append`, `merge`, `joinby`, or `convertonly` (default) |
| `directory(path)` | folder containing the input files (default: working directory) |
| `replace` | overwrite the `using` output file (abbreviation `rep`) |
| `filetype(ext)` | extension swept up: `csv` (default), `dta`, `txt`, `xlsx`, `xls`, `xml`, or any text extension |
| `fileid(newvar)` | variable holding each observation's source filename |
| `mtype(type)` | merge type: `1:1` (default), `m:m`, `1:m`, `m:1` |
| `mvars(varlist)` | key variables for `merge`/`joinby` (required with those methods; keys must be strings) |
| `_merge` | one match-status variable per file, named `_filestem` |
| `delimiter(char)` | `comma` (default), `tab`, or a character such as `";"` |
| `strictquotes` | skip the stray-quote rule: read delimited text with strict quote binding, no check, no fallback (see Limits) |
| `prefix()` / `suffix()` | decorate converted filenames |
| `tostring` | convert every variable to string during conversion, using each variable's display format (lossy for numerics; see Limits) |
| `keepconverted` | keep the per-file converted `.dta` copies (implied by `convertonly`) |
| `xmlopts(options)` | options passed to `xmluse` |

## Harmonization options (v2.0.0, `cmethod(append)` only)

| Option | What it does |
|---|---|
| `map(renames.csv)` | the rename map; activates the layer (year extraction, vintage renames, `year` variable, `[source]` chars, harmonization table) |
| `year(spec)` | year extraction: a starting position (`year(14)`) or a regex with a capture group (`year("run_([0-9][0-9][0-9][0-9])")`); default is the first 4-digit run 19xx/20xx |
| `strict` | error (111) instead of report when a mapped `oldname` is absent from a covered file |

The map file is a plain CSV with a header row and four columns:

```
oldname,newname,firstyear,lastyear
enroll_cnt,enrollment,,2020
mscore,mathscore,2019,2019
```

Blank `firstyear` or `lastyear` leaves that end of the window open. A row whose `oldname` equals its `newname` asserts presence (useful with `strict`). Matching is exact and case-sensitive. Keep the map file outside `directory()`, or it will be swept up as an input.

## Stored results

| Result | Contents |
|---|---|
| `r(n_files)` | number of files converted/combined |
| `r(output)` | path of the combined file (not `convertonly`) |
| `r(n_vars)` | number of variables in the panel, including `year` (`map()` only) |
| `r(n_missing)` | number of expected-but-absent oldname reports (`map()` only) |
| `r(years)` | distinct years stacked, ascending (`map()` only) |

## Limits, stated plainly

- Output goes to the `using` file on disk; your data in memory are preserved and restored, not replaced.
- Without `using`, the output is `combineall_output.dta` inside `directory()`. Every option is optional, so a bare `combineall` converts every `.csv` file in the working directory to `.dta` (`cmethod(convertonly)` is assumed).
- Text files: the first row holds variable names when some column below it holds numbers. When every column is text, `combineall` uses the first row as names when every cell of that row is non-blank text that is not a number. A header-less file whose first row is all text is read the same way, so give such files a header row.
- Appends use `force` (engine semantics since 2011), so a string/numeric type conflict across files coerces the offending values to missing instead of stopping. This holds under `map()` too, and differs from a bare `append`. Check the harmonization table for unexpected gaps.
- `tostring` is lossy for numerics. The conversion runs as `tostring varname, force replace usedisplayformat`, so each value is written as its display format renders it rather than at full precision: a double holding 1/3 under the default `%10.0g` becomes the string `.33333333`, and `destring` cannot recover the dropped digits. The conversion runs quietly, so `tostring`'s own loss-of-information message is not shown. Reserve `tostring` for identifier-like columns whose type wobbles across files.
- `merge`/`joinby` keys must be strings (the seeded empty master creates them as strings); `joinby` needs `unmatched(both)` to be useful.
- With `filetype(dta)` and no `prefix()`/`suffix()`, the converted copy is the source file itself, so `fileid()`, `tostring`, and `map()` renames write back into the sources.
- One year per file, taken from the filename; files containing multiple years should be split upstream. Under `map()`, a file that already contains a variable named `year` stops with an error and a hint to move it aside with a map row.
- No subdirectory recursion.
- Delimited text (and the `map()` CSV) is read once with `bindquote(strict)`, so a quoted field may contain the delimiter or a line break and stays one cell. Strict binding also treats one stray unmatched double quote (an inch mark, as in `1,5" screen,10`) as the start of a quoted field, so later rows can fold into one cell with no error. Unless `strictquotes` is given, `combineall` then applies one stray-quote rule:
  - If no string cell contains a line break, the strict result is kept (one read of the file, nothing printed).
  - Otherwise each cell with a line break is split at its line breaks. A line after the first looks like a data row when it holds at least k-1 delimiters, where k is the number of columns of the strict read and the delimiter is the one set by `delimiter()`. When k <= 2, the line must also start with an id-like token (digits, optionally after up to four letters and a `_` or `-`, such as `17`, `Q12`, `id_003`, or `2024-001`), and the file's first column must hold such values.
  - If any line looks like a data row, `combineall` warns, naming the file, the row and column of the strict read where the joined cell starts, and the strict and loose row counts, and keeps the default loose result. Every row survives, but the cell holding the stray quote runs to the end of its line, so repair that line upstream.
  - If none does, the line breaks are genuine multi-line text: the strict result is kept and nothing is printed.

  A file with both a genuine multi-line field and a stray quote gets the warning and the loose result (the stray-quote reading wins, so the multi-line field splits too). A genuine multi-line field whose later line happens to hold k-1 delimiters (two commas in a three-column file) is also read as a stray quote; use `strictquotes` for such a file. `strictquotes` applies to every delimited file in the run.

## Lineage and license

combineall v1.0.0: April 2011, Eric A. Booth. v2.0.0: 2026, Eric A. Booth, Sr Researcher, Texas 2036 (eric.a.booth@gmail.com) and Elizabeth Teas, Sr Research Scientist, Far Harbor, LLC (elizabeth@farharbor.com). v2.0.0 replaces the short-lived `panelstack` package; its `map()`/`year()`/`strict` layer now lives here.

MIT. Copyright (c) 2026 Eric A. Booth. See [LICENSE](LICENSE).

## Changes

- **2.0.3 (2026-11-09):** a text file whose columns are all text keeps its header row as variable names. Before this, `import delimited` named such columns `v1`, `v2`, ... and kept the header as the first row, so `map()` renames never matched. The documented abbreviation `rep` for `replace` now works (it needed `repl`, and under `merge`/`joinby` a short `rep` was passed on to `merge`). The default output path has no doubled slash when `directory()` ends in `/`, and the converted-files folder prints as plain text instead of a `{browse}` link. The test battery finds the package from its first argument, the working directory, or the adopath.
- **2.0.2 (2026-11-09):** delimited files (and the `map()` CSV) are read with `bindquote(strict)`. Before this, a properly quoted field that contained a line break, such as a free-text survey answer, split into extra rows, which could also push the header row into the data and leave `v1`, `v2`, ... as variable names, with no error.
  A stray-quote rule catches an unmatched quote such as an inch mark: when a line inside a multi-line cell looks like a data row (at least k-1 delimiters; for k <= 2 also an id-like leading token), `combineall` warns and keeps the loose result. Genuine multi-line fields keep the strict result silently, and a file with no line breaks in any cell is read once. The new `strictquotes` option skips the rule.
