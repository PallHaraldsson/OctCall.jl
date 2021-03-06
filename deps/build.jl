using VersionParsing, Libdl

# JuliaInterop/Cxx.jl#166: this must be a global setting
if something(tryparse(Int, get(ENV, "JULIA_CXX_RTTI", "0")), 0) ≤ 0
    startup_jl = abspath(first(DEPOT_PATH), "config", "startup.jl")
    error("JULIA_CXX_RTTI environment variable must be 1 for OctCall.jl; add ENV[\"JULIA_CXX_RTTI\"]=1 to $startup_jl")
end

prefsfile = joinpath(first(DEPOT_PATH), "prefs", "OctCall")
mkpath(dirname(prefsfile))

MKOCTFILE = get(ENV, "MKOCTFILE", isfile(prefsfile) ? readchomp(prefsfile) : Sys.which("mkoctfile"))

MKOCTFILE === nothing && error("mkoctfile not found; make sure Octave is installed and in your PATH, or set the MKOCTFILE environment variable")
Sys.isexecutable(MKOCTFILE) || error("$MKOCTFILE is not executable")

OCTAVE_VERSION = vparse(readchomp(`$MKOCTFILE --version`))
OCTAVE_VERSION ≥ v"5" || error("octave version 5 or later is required; $OCTAVE_VERSION is not supported")

octavevar(var) = readchomp(`mkoctfile -p $var`)
octavevars(var) = Base.shell_split(octavevar(var))

include_dirs = [joinpath(octavevar("INCLUDEDIR"),"octave-$OCTAVE_VERSION"); octavevar("INCLUDEDIR"); map(s -> s[3:end], filter(s -> startswith(s, "-I"), octavevars("CPPFLAGS") ))]
lib_dirs = [joinpath(octavevar("LIBDIR"),"octave",string(OCTAVE_VERSION));octavevar("LIBDIR"); map(s -> s[3:end], filter(s -> startswith(s, "-L"), octavevars("LDFLAGS") ))]
libs = map(s -> s[3:end], filter(s -> startswith(s, "-l"), octavevars("OCTAVE_LIBS")))

function _findlib(name, libs)
    lib_names = sort!([s for s in libs if occursin(name, s)], by=length)
    isempty(lib_names) && error("lib$name not found in $libs")
    lib_name = endswith(lib_names[1], dlext) ? lib_names[1] : lib_names[1] * '.' * dlext
    if isabspath(lib_name)
        return lib_name
    else
        if !startswith(lib_name, "lib")
            lib_name = "lib" * lib_name
        end
        lib_path = findfirst(ispath, joinpath.(lib_dirs, lib_name))
        lib_path === nothing && return dlpath(lib_name) # look in default search path
        return abspath(lib_dirs[lib_path], lib_name)
    end
end
findlib(name, libs) = _findlib(name, libs)[1:end-length(dlext)-1]

liboctave = findlib("octave", libs)
liboctinterp = findlib("octinterp", libs)

oct_h_path = findfirst(ispath, joinpath.(include_dirs, "octave", "oct.h"))
oct_h_dir = oct_h_path === nothing ? nothing : abspath(include_dirs[oct_h_path])

function write_if_changed(filename, contents)
    if !isfile(filename) || read(filename, String) != contents
        write(filename, contents)
    end
end

deps = """
const MKOCTFILE = $(repr(MKOCTFILE))
const OCTAVE_VERSION = $(repr(OCTAVE_VERSION))
const liboctave = $(repr(liboctave))
const liboctinterp = $(repr(liboctinterp))
const oct_h_dir = $(repr(oct_h_dir))
"""
write_if_changed("deps.jl", deps)
write_if_changed(prefsfile, MKOCTFILE)
