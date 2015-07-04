import macros, streams

when not defined(nimnode):
    type NimNode = PNimrodNode

{.push overflowchecks: off.}
proc xinc*(c: var char) {.inline.} = inc c
proc xdec*(c: var char) {.inline.} = dec c
{.pop.}

proc readCharEOF*(input: Stream): char =
    result = input.readChar
    if result == '\0': # Streams return 0 for EOF
        result = '\255'  # BF assumes EOF to be -1

proc compile(code: string, input, output: string): NimNode {.compiletime.} =
    var stmts = @[newStmtList()]
    template addStmt(text): stmt =
        stmts[stmts.high].add parseStmt(text)

    addStmt """
        when not compiles(newStringStream()):
            static:
                quit("Error: Import the streams module to compile brainfuck code", 1)
    """
    addStmt "var inpStream = " & input
    addStmt "var outStream = " & output
    addStmt "var tape: array[1_000_000, char]"
    addStmt "var tapePos = 0"
    for c in code:
        case c
        of '+': addStmt "xinc tape[tapePos]"
        of '-': addStmt "xdec tape[tapePos]"
        of '>': addStmt "inc tapePos"
        of '<': addStmt "dec tapePos"
        of '.': addStmt "outStream.write tape[tapePos]"
        of ',': addStmt "tape[tapePos] = inpStream.readCharEOF"
        of '[': stmts.add newStmtList()
        of ']':
            var loop = newNimNode(nnkWhileStmt)
            loop.add parseExpr("tape[tapePos] != '\\0'")
            loop.add stmts.pop
            stmts[stmts.high].add loop
        else: discard
    result = stmts[0]
    #echo result.repr

macro compileFile*(filename: string): stmt =
    compile(staticRead(filename.strval), "stdin.newFileStream", "stdout.newFileStream")

macro compileFile*(filename: string; input, output: expr): stmt =
    result = compile(staticRead(filename.strval),
        "newStringStream(" & $input & ")", "newStringStream()")
    result.add parseStmt($output & " = outStream.data")

macro compileString*(code: string): stmt =
    compile($code, "stdin.newFileStream", "stdout.newFileStream")

macro compileString*(code: string; input, output: expr): stmt =
    result = compile($code, "newStringStream(" & $input & ")", "newStringStream()")
    result.add parseStmt($output & " = outStream.data")


proc interpret*(code: string, input, output: Stream) =
    ## Interprets the brainfuck `code` string, reading from `input` and writing
    ## to `output`.
    ##
    ## Example:
    ##
    ## .. code:: nim
    ##   var inpStream = newStringStream("Hello World!\n")
    ##   var outStream = newFileStream(stdout)
    ##   interpret(readFile("examples/rot13.b"), inpStream, outStream)
    var
        tape = newSeq[char]()
        codePos = 0
        tapePos = 0

    proc run(skip = false): bool =
        while tapePos >= 0 and codePos < code.len:
            if tapePos >= tape.len:
                tape.add '\0'
            if code[codePos] == '[':
                inc codePos
                let oldPos = codePos
                while run(tape[tapePos] == '\0'):
                    codePos = oldPos
            elif code[codePos] == ']':
                return tape[tapePos] != '\0'
            elif not skip:
                case code[codePos]
                of '+': xinc tape[tapePos]
                of '-': xdec tape[tapePos]
                of '>': inc tapePos
                of '<': dec tapePos
                of '.': output.write tape[tapePos]
                of ',': tape[tapePos] = input.readCharEOF
                else: discard

            inc codePos

    discard run()

proc interpret*(code, input: string): string =
    ## Interprets the brainfuck `code` string, reading from `input` and returning
    ## the result directly.
    var outStream = newStringStream()
    interpret(code, input.newStringStream, outStream)
    result = outStream.data

proc interpret*(code: string) =
    ## Interprets the brainfuck `code` string, reading from stdin and writing to
    ## stdout.
    interpret(code, stdin.newFileStream, stdout.newFileStream)

when isMainModule:
    import docopt, tables, strutils

    proc mandelbrot = compileFile("../examples/mandelbrot.b")

    let doc = """
brainfuck

Usage:
    brainfuck mandelbrot
    brainfuck interpret [<file.b>]
    brainfuck (-h | --help)
    brainfuck (-v | --version)

Options:
    -h --help     Show this screen.
    -v --version  Show version.
"""
    let args = docopt(doc, version = "brainfuck 1.0")
    if args["mandelbrot"]:
        mandelbrot()

    elif args["interpret"]:
        let code = if args["<file.b>"]: readFile($args["<file.b>"])
                   else: readAll(stdin)
        interpret(code)

