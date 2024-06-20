@echo off

set "app=Pentago"

if "%1" equ "debug" (
	set "ml=/D_DEBUG /Zi"
	set "link=/DEBUG"
) else (
	set "ml=/DNDEBUG"
	set "link=/OPT:REF /OPT:ICF"
)

if not exist "%~dp0..\output" mkdir "%~dp0..\output"

pushd "%~dp0..\output"
rc /nologo /fo "%app%.res" "..\res\%app%.rc"
ml64 /nologo /WX /W3 "..\src\pentago.asm" /Fe"%app%" /link /nologo "%app%.res" /INCREMENTAL:NO /SUBSYSTEM:CONSOLE /FIXED /merge:_RDATA=.rdata

del *.obj *.lnk >nul *.res >nul
popd