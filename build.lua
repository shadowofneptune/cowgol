vars.cflags = { "-g", "-O0" }
vars.ldflags = { "-lm", "-g" }

vars.toolchains = {
	"oldcom-cpm-8080",
	"oldcom-linux-80386",
	"oldcom-linux-thumb2",
	"oldcom-cgen",
	"cowcom-cpm-8080",
}

installable {
	name = "all",
	map = {
		["bin/cpmemu"] = "tools/cpmemu+cpmemu",
		["bin/tubeemu"] = "tools/tubeemu+tubeemu",
		["bin/zmac"] = "third_party/zmac+zmac",
		["bin/lemon"] = "third_party/lemon+lemon",
		["bin/lemon-cowgol"] = "third_party/lemon+lemon-cowgol",
		["bin/newgen"] = "tools/newgen+newgen",
		["bin/newgen-cowgol"] = "tools/newgen+newgen-cowgol",
		"src/cowcom+all-cowcoms",
		"src/oldcom+all-oldcoms",
		"src/cowlink+all-cowlinks",
	}
}

normalrule {
	name = "tests",
	ins = {
		"tests+tests"
	},
	outleaves = {
		"stamp"
	},
	commands = {
		"touch %{outs}"
	}
}

