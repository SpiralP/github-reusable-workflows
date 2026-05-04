def norm:
  if type == "string" then [., {}]
  elif (. | length) == 1 then [.[0], {}]
  else . end;

# `@semantic-release/exec` entries stay distinct (keyed by index);
# every other plugin name groups for config merging.
def pkey($i):
  norm as [$n, $_] |
  if $n == "@semantic-release/exec" then "exec#\($i)" else $n end;

def merge_plugins($a; $b):
  ([($a // []), ($b // [])] | add) as $all
  | reduce range(0; $all|length) as $i ({order: [], byKey: {}};
      ($all[$i] | norm) as [$n, $c]
      | ($all[$i] | pkey($i)) as $k
      | if .byKey[$k] then
          .byKey[$k] = [$n, (.byKey[$k][1] * $c)]
        else
          .order += [$k] | .byKey[$k] = [$n, $c]
        end)
  | [.order[] as $k | .byKey[$k]];

(.[0] * .[1]) * { plugins: merge_plugins(.[0].plugins; .[1].plugins) }
