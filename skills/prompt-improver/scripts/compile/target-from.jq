# scripts/compile/target-from.jq
# The target for a cell with "target_from": the file that the named slot points at.
# A file entity gives its path directly. An identifier gives the non-test file
# that defines it (from its git grep references), else the non-test file that
# mentions it most. Prints the path, or nothing.
#
# jq -r --arg s <slot> --slurpfile c cands.json -f target-from.jq understanding.json

def is_test: test("(^|/)(tests?|specs?|__tests__|testing)/|[._-](test|spec)\\.[A-Za-z0-9]+$|(^|/)test_[^/]*$|_test\\.[A-Za-z0-9]+$|smoke-test");
def defines($n):
  (sub("^[[:space:]]+"; "")) as $t
  | any(["", "function ", "def ", "func ", "fn ", "class ", "const ", "let ", "var ", "export ", "export function ", "async function ", "local ", "readonly "][];
        . as $k | ($t | startswith($k + $n)) and (($t | ltrimstr($k + $n) | .[0:1]) as $c | ($c == "(" or $c == " " or $c == "=" or $c == ":" or $c == "{")));

(.slots[$s] // null) as $v
| if $v == null then empty
  elif (($v.paths // []) | length) == 1 then $v.paths[0]
  else
    ([$c[0].entities[] | select(.id == $v.source) | (.refs // [])[]]
     | map(split(":") as $p | {path: $p[0], text: ($p[2:] | join(":"))})
     | map(select(.path | test("\\.(md|mdx|rst|txt|json|jsonl|ya?ml|lock)$") | not))) as $refs
    | ([$refs[] | select(.path | is_test | not)]) as $prod
    | (([$prod[] | select(.text | defines($v.value))] | .[0].path)
       // ($prod | group_by(.path) | sort_by(-length) | .[0][0].path)
       // empty)
  end
