-- Headless test runner for Lune (https://lune-org.github.io/docs).
-- Loads the place built by Rojo, so modules resolve exactly as in Roblox (`require(script.Parent.X)`),
-- then runs every tests/**/*.spec.luau file. Specs use the TestEZ style: describe/it/expect.
--
-- Usage: lune run tests/runner.luau [path/to/place.rbxl]   (see scripts/test.sh)

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local placePath = process.args[1] or "build/GateZillion.rbxl"
local game = roblox.deserializePlace(fs.readFile(placePath))

-- Module loading ------------------------------------------------------------------------------

local moduleCache: { [string]: any } = {}
local loading: { [string]: boolean } = {}
local requireModule

local function moduleEnvironment(instance: any): { [string]: any }
	return {
		script = instance,
		require = requireModule,
		game = game,
		workspace = game:GetService("Workspace"),
	}
end

function requireModule(target: any): any
	if typeof(target) ~= "Instance" then
		error(`require expects a ModuleScript instance, got {typeof(target)}`, 2)
	end
	if not target:IsA("ModuleScript") then
		error(`{target:GetFullName()} is not a ModuleScript`, 2)
	end
	local key = target:GetFullName()
	if moduleCache[key] ~= nil then
		return moduleCache[key]
	end
	if loading[key] then
		error(`cyclic require of {key}`, 2)
	end
	loading[key] = true
	local chunk = luau.load(target.Source, {
		debugName = key,
		environment = moduleEnvironment(target),
	})
	local result = chunk()
	loading[key] = nil
	moduleCache[key] = result
	return result
end

-- Minimal TestEZ-compatible API -------------------------------------------------------------------

type TestCase = { name: string, fn: () -> () }
type Suite = {
	name: string,
	tests: { TestCase },
	children: { Suite },
	beforeEach: { () -> () },
	afterEach: { () -> () },
	parent: Suite?,
}

local function newSuite(name: string, parent: Suite?): Suite
	return { name = name, tests = {}, children = {}, beforeEach = {}, afterEach = {}, parent = parent }
end

local currentSuite: Suite = newSuite("root", nil)

local function formatValue(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local function expect(actual: any)
	local negated = false
	local expectation = {}

	local function assertThat(passed: boolean, message: string, negatedMessage: string)
		if negated then
			passed = not passed
			message = negatedMessage
		end
		if not passed then
			error(message, 3)
		end
	end

	function expectation.equal(expected: any)
		assertThat(
			actual == expected,
			`expected {formatValue(expected)}, got {formatValue(actual)}`,
			`expected value to not equal {formatValue(expected)}`
		)
		return expectation
	end

	function expectation.ok()
		assertThat(
			actual ~= nil and actual ~= false,
			`expected a truthy value, got {formatValue(actual)}`,
			`expected a falsy value, got {formatValue(actual)}`
		)
		return expectation
	end

	function expectation.near(expected: number, limit: number?)
		local tolerance = limit or 1e-7
		assertThat(
			type(actual) == "number" and math.abs(actual - expected) <= tolerance,
			`expected {formatValue(actual)} to be within {tolerance} of {expected}`,
			`expected {formatValue(actual)} to not be near {expected}`
		)
		return expectation
	end

	function expectation.a(typeName: string)
		assertThat(
			typeof(actual) == typeName,
			`expected a {typeName}, got {typeof(actual)}`,
			`expected value to not be a {typeName}`
		)
		return expectation
	end
	expectation.an = expectation.a

	function expectation.throw(substring: string?)
		local ok, err = pcall(actual)
		local matched = not ok and (substring == nil or string.find(tostring(err), substring, 1, true) ~= nil)
		assertThat(
			matched,
			if ok
				then "expected function to throw"
				else `expected error containing {formatValue(substring)}, got {tostring(err)}`,
			`expected function to not throw, got {tostring(err)}`
		)
		return expectation
	end

	return setmetatable(expectation, {
		__index = function(self, key)
			if key == "never" then
				negated = not negated
				return self
			elseif key == "to" or key == "be" or key == "been" or key == "have" or key == "was" or key == "at" then
				return self
			end
			error(`unknown expectation {tostring(key)}`, 2)
		end,
	})
end

local testGlobals = {
	describe = function(name: string, fn: () -> ())
		local suite = newSuite(name, currentSuite)
		table.insert(currentSuite.children, suite)
		local previous = currentSuite
		currentSuite = suite
		fn()
		currentSuite = previous
	end,
	it = function(name: string, fn: () -> ())
		table.insert(currentSuite.tests, { name = name, fn = fn })
	end,
	beforeEach = function(fn: () -> ())
		table.insert(currentSuite.beforeEach, fn)
	end,
	afterEach = function(fn: () -> ())
		table.insert(currentSuite.afterEach, fn)
	end,
	expect = expect,
}

-- Spec discovery and execution ------------------------------------------------------------------

local function findSpecs(directory: string, out: { string })
	local entries = fs.readDir(directory)
	table.sort(entries)
	for _, entry in entries do
		local path = `{directory}/{entry}`
		if fs.isDir(path) then
			findSpecs(path, out)
		elseif string.match(entry, "%.spec%.luau$") then
			table.insert(out, path)
		end
	end
end

local specs = {}
findSpecs("tests", specs)

for _, path in specs do
	local environment = table.clone(testGlobals)
	environment.game = game
	environment.workspace = game:GetService("Workspace")
	environment.require = requireModule
	local chunk = luau.load(fs.readFile(path), { debugName = path, environment = environment })
	local fileSuite = newSuite(path, currentSuite)
	table.insert(currentSuite.children, fileSuite)
	local previous = currentSuite
	currentSuite = fileSuite
	local result = chunk()
	if type(result) == "function" then
		result()
	end
	currentSuite = previous
end

local passed, failed = 0, 0
local failures: { string } = {}

local function collectHooks(suite: Suite, field: "beforeEach" | "afterEach"): { () -> () }
	local chain = {}
	local node: Suite? = suite
	while node do
		table.insert(chain, 1, node)
		node = node.parent
	end
	local hooks = {}
	for _, item in chain do
		for _, hook in item[field] do
			table.insert(hooks, hook)
		end
	end
	return hooks
end

local function run(suite: Suite, path: string)
	for _, test in suite.tests do
		local name = `{path} > {test.name}`
		local ok, err = pcall(function()
			for _, hook in collectHooks(suite, "beforeEach") do
				hook()
			end
			test.fn()
			for _, hook in collectHooks(suite, "afterEach") do
				hook()
			end
		end)
		if ok then
			passed += 1
			print(`  PASS  {name}`)
		else
			failed += 1
			print(`  FAIL  {name}\n        {tostring(err)}`)
			table.insert(failures, name)
		end
	end
	for _, child in suite.children do
		run(child, if path == "" then child.name else `{path} > {child.name}`)
	end
end

run(currentSuite, "")

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	for _, name in failures do
		print(`  failed: {name}`)
	end
	process.exit(1)
end
