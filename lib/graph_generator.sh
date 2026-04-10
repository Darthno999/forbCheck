#!/bin/bash

# ==============================================================================
#  FORBCHECK GRAPH GENERATOR MODULE
# ==============================================================================

collect_callgraph_files() {
    local files=()
    local file

    if [ -n "$SPECIFIC_FILES" ]; then
        for file in $SPECIFIC_FILES; do
            [ -f "$file" ] || continue
            case "$file" in
                *.c) files+=("$file") ;;
            esac
        done
    else
        while IFS= read -r file; do
            [ -n "$file" ] && files+=("$file")
        done < <(find . -maxdepth 5 -type f -name "*.c" | sort)
    fi

    printf '%s\n' "${files[@]}"
}

generate_callgraph_json() {
    ACTIVE_PRESET_PATH="${ACTIVE_PRESET:-}" perl - "$@" <<'PERL'
use strict;
use warnings;
use JSON::PP qw(encode_json);

sub sanitize_c {
    my ($text) = @_;
    my $out = '';
    my $len = length($text);
    my $i = 0;
    my $state = 'code';

    while ($i < $len) {
        my $ch = substr($text, $i, 1);
        my $next = $i + 1 < $len ? substr($text, $i, 2) : $ch;

        if ($state eq 'code') {
            if ($next eq '//') {
                $out .= '  ';
                $i += 2;
                $state = 'line_comment';
                next;
            }
            if ($next eq '/*') {
                $out .= '  ';
                $i += 2;
                $state = 'block_comment';
                next;
            }
            if ($ch eq '"') {
                $out .= ' ';
                $i++;
                $state = 'dquote';
                next;
            }
            if ($ch eq q{'}) {
                $out .= ' ';
                $i++;
                $state = 'squote';
                next;
            }
            $out .= $ch;
            $i++;
            next;
        }

        if ($state eq 'line_comment') {
            if ($ch eq "\n") {
                $out .= "\n";
                $state = 'code';
            } else {
                $out .= ' ';
            }
            $i++;
            next;
        }

        if ($state eq 'block_comment') {
            if ($next eq '*/') {
                $out .= '  ';
                $i += 2;
                $state = 'code';
            } else {
                $out .= $ch eq "\n" ? "\n" : ' ';
                $i++;
            }
            next;
        }

        if ($state eq 'dquote' || $state eq 'squote') {
            my $quote = $state eq 'dquote' ? '"' : q{'};

            if ($ch eq '\\') {
                my $pair = substr($text, $i, 2);
                $pair = $ch if length($pair) == 1;
                $pair =~ s/[^\n]/ /g;
                $out .= $pair;
                $i += length($pair);
                next;
            }

            if ($ch eq $quote) {
                $out .= ' ';
                $i++;
                $state = 'code';
                next;
            }

            $out .= $ch eq "\n" ? "\n" : ' ';
            $i++;
            next;
        }
    }

    return $out;
}

sub match_brace_end {
    my ($text, $open_index) = @_;
    my $depth = 1;
    my $i = $open_index + 1;
    my $len = length($text);

    while ($i < $len) {
        my $ch = substr($text, $i, 1);
        if ($ch eq '{') {
            $depth++;
        } elsif ($ch eq '}') {
            $depth--;
            return $i if $depth == 0;
        }
        $i++;
    }

    return -1;
}

sub count_lines_before {
    my ($text, $index) = @_;
    my $prefix = substr($text, 0, $index);
    return 1 + ($prefix =~ tr/\n//);
}

sub load_forbidden_names {
    my $preset_path = $ENV{ACTIVE_PRESET_PATH} || '';
    return {} if !$preset_path || !-f $preset_path;

    open my $preset_fh, '<', $preset_path or return {};
    local $/ = undef;
    my $raw = <$preset_fh>;
    close $preset_fh;

    return {} if !defined $raw || $raw eq '';

    $raw =~ s/#.*$//mg;

    if ($raw =~ /\bALL_MATH\b/) {
        my $math_funcs = join ' ', qw(
            cos sin tan acos asin atan atan2 cosh sinh tanh exp frexp ldexp
            log log10 modf pow sqrt ceil fabs floor fmod round trunc abs labs
        );
        $raw =~ s/\bALL_MATH\b//g;
        $raw .= " $math_funcs";
    }

    $raw =~ s/\b(?:BLACKLIST_MODE|ALL_MLX|ALL_MATH)\b//g;
    $raw =~ tr/,/ /;

    my %forbidden = map { $_ => 1 }
        grep { defined $_ && $_ ne '' }
        split /\s+/, $raw;

    return \%forbidden;
}

my %defs;
my @functions;
my %seen_name;
my %keywords = map { $_ => 1 } qw(if for while switch return sizeof case do else);
my $forbidden_names = load_forbidden_names();

for my $file (@ARGV) {
    open my $fh, '<', $file or next;
    local $/ = undef;
    my $content = <$fh>;
    close $fh;

    my $clean = sanitize_c($content);

    while ($clean =~ /
        (?:
            ^ | [;\}\n]
        )
        \s*
        (?:
            [A-Za-z_][\w\s\*\n]*?
            [\s\*]+
        )?
        ([A-Za-z_]\w*)
        \s*
        \(
            ([^;{}()]*(?:\([^()]*\)[^;{}()]*)*)
        \)
        \s*
        \{
    /xgms) {
        my $name = $1;
        next if $keywords{$name};

        my $open_index = pos($clean) - 1;
        my $close_index = match_brace_end($clean, $open_index);
        next if $close_index < 0;

        my $line = count_lines_before($clean, $-[1]);
        my $body = substr($clean, $open_index + 1, $close_index - $open_index - 1);

        next if $seen_name{$name}++;

        $defs{$name} = {
            id   => $name,
            file => $file,
            line => $line,
        };

        push @functions, {
            id   => $name,
            body => $body,
        };
    }
}

my %edges;
my %incoming;
my %is_user_func;

for my $func (@functions) {
    $is_user_func{$func->{id}} = 1;
}

for my $func (@functions) {
    my $source = $func->{id};
    my $body = $func->{body};

    while ($body =~ /\b([A-Za-z_]\w*)\s*\(/g) {
        my $target = $1;
        next if $keywords{$target};
        next if $edges{$source}{$target};

        # Add external functions as nodes if not already defined
        if (!exists $defs{$target}) {
            $defs{$target} = {
                id => $target,
                file => $func->{file},
                line => 0,
            };
            push @functions, { id => $target, body => '' };
        }

        $edges{$source}{$target} = 1;
        $incoming{$target}++;
    }
}

my @nodes = map {
    +{
        id        => $defs{$_}{id},
        file      => $defs{$_}{file},
        line      => $defs{$_}{line},
        callCount => $incoming{$_} || 0,
        forbidden => $forbidden_names->{$_} ? JSON::PP::true : JSON::PP::false,
        isUserFunction => $is_user_func{$_} ? JSON::PP::true : JSON::PP::false,
    }
} sort keys %defs;

my @links;
for my $source (sort keys %edges) {
    for my $target (sort keys %{ $edges{$source} }) {
        push @links, {
            source => $source,
            target => $target,
        };
    }
}

print encode_json({
    nodes => \@nodes,
    edges => \@links,
});
PERL
}

generate_callgraph_report() {
    local graph_file="$PWD/forb_callgraph.html"
    local file_list json_data
    local files=()
    local file

    file_list=$(collect_callgraph_files | sed '/^$/d')
    if [ -z "$file_list" ]; then
        echo -ne "\n${YELLOW}No C source files found for call graph generation.${NC}\n"
        return 0
    fi

    while IFS= read -r file; do
        [ -n "$file" ] && files+=("$file")
    done <<< "$file_list"

    json_data=$(generate_callgraph_json "${files[@]}")
    if [ -z "$json_data" ]; then
        echo -ne "\n${RED}Call graph generation failed: unable to build graph dataset.${NC}\n"
        return 1
    fi

    cat <<EOF > "$graph_file"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>ForbCheck Call Graph</title>
  <style>
    :root {
      --bg: #0a0a0f;
      --panel: rgba(13, 16, 24, 0.92);
      --panel-border: rgba(0, 212, 255, 0.18);
      --cyan: #00d4ff;
      --magenta: #ff00aa;
      --orange: #ff9500;
      --red: #ff3333;
      --text: #e0e0e0;
      --muted: #7f88a8;
      --edge: rgba(255,255,255,0.12);
      --shadow: 0 0 24px rgba(0, 212, 255, 0.18);
    }

    * {
      box-sizing: border-box;
    }

    html, body {
      margin: 0;
      width: 100%;
      height: 100%;
      overflow: hidden;
      background:
        radial-gradient(circle at top left, rgba(0, 212, 255, 0.12), transparent 28%),
        radial-gradient(circle at bottom right, rgba(255, 0, 170, 0.1), transparent 24%),
        linear-gradient(135deg, #06070b 0%, #0a0a0f 48%, #0e1018 100%);
      color: var(--text);
      font-family: Menlo, Monaco, monospace;
    }

    body::before {
      content: "";
      position: fixed;
      inset: 0;
      pointer-events: none;
      background-image:
        linear-gradient(rgba(255, 255, 255, 0.02) 1px, transparent 1px),
        linear-gradient(90deg, rgba(255, 255, 255, 0.02) 1px, transparent 1px);
      background-size: 28px 28px;
      opacity: 0.2;
    }

    #app {
      position: relative;
      width: 100%;
      height: 100%;
    }

    #controls,
    #info,
    #legend {
      position: absolute;
      z-index: 2;
      backdrop-filter: blur(18px);
      background: var(--panel);
      border: 1px solid var(--panel-border);
      border-radius: 18px;
      box-shadow: var(--shadow);
    }

    #controls {
      top: 18px;
      left: 18px;
      width: min(460px, calc(100vw - 36px));
      padding: 16px 18px;
    }

    #title {
      margin: 0 0 12px;
      color: var(--cyan);
      font-size: 20px;
      letter-spacing: 0.08em;
      text-transform: uppercase;
    }

    #subtitle {
      margin: 0 0 14px;
      color: var(--muted);
      font-size: 12px;
      line-height: 1.5;
    }

    #search {
      width: 100%;
      padding: 12px 14px;
      border: 1px solid rgba(0, 212, 255, 0.25);
      border-radius: 12px;
      background: rgba(255, 255, 255, 0.04);
      color: var(--text);
      font: inherit;
      outline: none;
      transition: border-color 160ms ease, box-shadow 160ms ease;
    }

    #search:focus {
      border-color: rgba(0, 212, 255, 0.7);
      box-shadow: 0 0 0 3px rgba(0, 212, 255, 0.12);
    }

    #stats {
      display: flex;
      gap: 10px;
      margin-top: 12px;
      flex-wrap: wrap;
    }

    .stat {
      min-width: 118px;
      padding: 10px 12px;
      border-radius: 12px;
      background: rgba(255, 255, 255, 0.03);
      border: 1px solid rgba(255, 255, 255, 0.04);
    }

    .stat-label {
      display: block;
      color: var(--muted);
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: 0.08em;
    }

    .stat-value {
      display: block;
      margin-top: 4px;
      color: var(--text);
      font-size: 18px;
    }

    #info {
      top: 18px;
      right: 18px;
      width: min(360px, calc(100vw - 36px));
      max-height: calc(100vh - 36px);
      padding: 16px 18px;
      overflow: auto;
    }

    #legend {
      left: 18px;
      bottom: 18px;
      width: min(280px, calc(100vw - 36px));
      padding: 14px 16px;
    }

    #legend h2 {
      margin: 0 0 10px;
      color: var(--cyan);
      font-size: 14px;
      letter-spacing: 0.08em;
      text-transform: uppercase;
    }

    .legend-item {
      display: flex;
      align-items: center;
      gap: 10px;
      color: var(--text);
      font-size: 12px;
      line-height: 1.6;
    }

    .legend-item + .legend-item {
      margin-top: 8px;
    }

    .legend-dot,
    .legend-line {
      display: inline-block;
      flex: 0 0 auto;
    }

    .legend-dot {
      width: 12px;
      height: 12px;
      border-radius: 999px;
      border: 2px solid transparent;
    }

    .legend-dot.user {
      border-color: var(--cyan);
      background: rgba(0, 212, 255, 0.25);
    }

    .legend-dot.forbidden {
      border-color: var(--red);
      background: rgba(255, 51, 51, 0.3);
    }

    .legend-dot.external {
      border-color: var(--orange);
      background: rgba(255, 149, 0, 0.25);
    }

    .legend-line {
      width: 20px;
      height: 0;
      border-top: 3px solid transparent;
      border-radius: 999px;
    }

    .legend-line.outgoing {
      border-top-color: var(--cyan);
    }

    .legend-line.incoming {
      border-top-color: var(--orange);
    }

    #info h2 {
      margin: 0 0 10px;
      color: var(--magenta);
      font-size: 18px;
    }

    #info .meta {
      margin: 0 0 14px;
      color: var(--muted);
      font-size: 12px;
      line-height: 1.5;
      white-space: pre-wrap;
      word-break: break-word;
    }

    #info h3 {
      margin: 16px 0 8px;
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.08em;
    }

    #info h3.section-outgoing {
      color: var(--cyan);
    }

    #info h3.section-incoming {
      color: var(--orange);
    }

    .section-indicator {
      display: inline-block;
      width: 8px;
      height: 8px;
      margin-right: 8px;
      border-radius: 999px;
      vertical-align: middle;
      background: currentColor;
      box-shadow: 0 0 10px currentColor;
    }

    #info ul {
      margin: 0;
      padding-left: 18px;
      color: var(--text);
      font-size: 13px;
      line-height: 1.6;
    }

    #info .empty {
      color: var(--muted);
      font-size: 13px;
    }

    #callsTo,
    #callsTo ul,
    #callsTo li {
      color: var(--cyan);
    }

    #callsFrom,
    #callsFrom ul,
    #callsFrom li {
      color: var(--orange);
    }

    svg {
      width: 100%;
      height: 100%;
      display: block;
      cursor: grab;
    }

    svg:active {
      cursor: grabbing;
    }

    .edge {
      stroke: var(--edge);
      stroke-width: 1px;
      stroke-opacity: 0.08;
    }

    .node {
      stroke: var(--cyan);
      stroke-width: 1.6px;
      fill: rgba(0, 212, 255, 0.2);
      filter: url(#node-glow);
      cursor: pointer;
      transition: opacity 160ms ease;
    }

    .node.selected {
      stroke-width: 2.4px;
      filter: url(#selected-glow);
    }

    .node.selected:not(.forbidden) {
      stroke: var(--magenta);
      fill: rgba(255, 0, 170, 0.22);
    }

    .node.forbidden {
      stroke: var(--red);
      stroke-width: 2px;
      fill: rgba(255, 51, 51, 0.3);
    }

    .node.external {
      stroke: var(--orange);
      stroke-width: 1.8px;
      fill: rgba(255, 149, 0, 0.25);
    }

    .node.match {
      filter: url(#search-glow);
    }

    .label {
      fill: var(--text);
      font-size: 11px;
      pointer-events: none;
      paint-order: stroke;
      stroke: rgba(10, 10, 15, 0.9);
      stroke-width: 3px;
      stroke-linejoin: round;
    }

    @media (max-width: 920px) {
      #controls,
      #info,
      #legend {
        width: calc(100vw - 24px);
        left: 12px;
        right: 12px;
      }

      #controls {
        top: 12px;
      }

      #info {
        top: auto;
        bottom: 12px;
        max-height: 42vh;
      }

      #legend {
        top: auto;
        bottom: calc(42vh + 24px);
      }
    }
  </style>
</head>
<body>
  <div id="app">
    <div id="controls">
      <h1 id="title">ForbCheck Call Graph</h1>
      <p id="subtitle">Interactive D3.js force graph of user-defined C functions in the current project. Search highlights matching nodes and clicking a node opens caller and callee details.</p>
      <input id="search" type="search" placeholder="Search functions or files..." autocomplete="off" spellcheck="false">
      <div id="stats">
        <div class="stat"><span class="stat-label">Functions</span><span class="stat-value" id="nodeCount">0</span></div>
        <div class="stat"><span class="stat-label">Calls</span><span class="stat-value" id="edgeCount">0</span></div>
      </div>
    </div>
    <div id="info">
      <h2>Selection</h2>
      <p class="meta" id="nodeMeta">Click a node to inspect its call relationships.</p>
      <h3 class="section-outgoing"><span class="section-indicator"></span>Functions Called</h3>
      <div id="callsTo"></div>
      <h3 class="section-incoming"><span class="section-indicator"></span>Functions Called By</h3>
      <div id="callsFrom"></div>
    </div>
    <div id="legend">
      <h2>Legend</h2>
      <div class="legend-item"><span class="legend-dot user"></span><span>User Function (local)</span></div>
      <div class="legend-item"><span class="legend-dot external"></span><span>External Authorized (lib)</span></div>
      <div class="legend-item"><span class="legend-dot forbidden"></span><span>Forbidden Function</span></div>
      <div class="legend-item"><span class="legend-line outgoing"></span><span>Calls (outgoing)</span></div>
      <div class="legend-item"><span class="legend-line incoming"></span><span>Called by (incoming)</span></div>
    </div>
    <svg id="graph" aria-label="Function call graph"></svg>
  </div>

  <script src="https://cdn.jsdelivr.net/npm/d3@7"></script>
  <script>
    const DATA = $json_data;

    const svg = d3.select("#graph");
    const width = window.innerWidth;
    const height = window.innerHeight;
    const nodeCountEl = document.getElementById("nodeCount");
    const edgeCountEl = document.getElementById("edgeCount");
    const searchEl = document.getElementById("search");
    const nodeMetaEl = document.getElementById("nodeMeta");
    const callsToEl = document.getElementById("callsTo");
    const callsFromEl = document.getElementById("callsFrom");

    nodeCountEl.textContent = DATA.nodes.length;
    edgeCountEl.textContent = DATA.edges.length;

    DATA.nodes = DATA.nodes.map((node) => ({
      ...node,
      radius: Math.max(8, 8 + (node.callCount || 0) * 3),
    }));

    const DEFAULT_EDGE_COLOR = "rgba(255,255,255,0.12)";
    const DEFAULT_EDGE_OPACITY = 0.08;
    const OUTGOING_EDGE_COLOR = "#00d4ff";
    const INCOMING_EDGE_COLOR = "#ff9500";

    const outgoing = new Map(DATA.nodes.map((node) => [node.id, []]));
    const incoming = new Map(DATA.nodes.map((node) => [node.id, []]));

    DATA.edges.forEach((edge) => {
      outgoing.get(edge.source)?.push(edge.target);
      incoming.get(edge.target)?.push(edge.source);
    });

    const defs = svg.append("defs");

    defs.append("filter")
      .attr("id", "node-glow")
      .append("feDropShadow")
      .attr("dx", 0)
      .attr("dy", 0)
      .attr("stdDeviation", 3)
      .attr("flood-color", "#00d4ff")
      .attr("flood-opacity", 0.35);

    defs.append("filter")
      .attr("id", "search-glow")
      .append("feDropShadow")
      .attr("dx", 0)
      .attr("dy", 0)
      .attr("stdDeviation", 6)
      .attr("flood-color", "#00d4ff")
      .attr("flood-opacity", 0.9);

    defs.append("filter")
      .attr("id", "selected-glow")
      .append("feDropShadow")
      .attr("dx", 0)
      .attr("dy", 0)
      .attr("stdDeviation", 7)
      .attr("flood-color", "#ff00aa")
      .attr("flood-opacity", 0.75);

    defs.append("marker")
      .attr("id", "arrow-default")
      .attr("viewBox", "0 -5 10 10")
      .attr("refX", 18)
      .attr("refY", 0)
      .attr("markerWidth", 7)
      .attr("markerHeight", 7)
      .attr("orient", "auto")
      .append("path")
      .attr("fill", DEFAULT_EDGE_COLOR)
      .attr("fill-opacity", DEFAULT_EDGE_OPACITY)
      .attr("d", "M0,-5L10,0L0,5");

    defs.append("marker")
      .attr("id", "arrow-outgoing")
      .attr("viewBox", "0 -5 10 10")
      .attr("refX", 18)
      .attr("refY", 0)
      .attr("markerWidth", 7)
      .attr("markerHeight", 7)
      .attr("orient", "auto")
      .append("path")
      .attr("fill", OUTGOING_EDGE_COLOR)
      .attr("fill-opacity", 0.95)
      .attr("d", "M0,-5L10,0L0,5");

    defs.append("marker")
      .attr("id", "arrow-incoming")
      .attr("viewBox", "0 -5 10 10")
      .attr("refX", 18)
      .attr("refY", 0)
      .attr("markerWidth", 7)
      .attr("markerHeight", 7)
      .attr("orient", "auto")
      .append("path")
      .attr("fill", INCOMING_EDGE_COLOR)
      .attr("fill-opacity", 0.95)
      .attr("d", "M0,-5L10,0L0,5");

    const root = svg.append("g");
    const edgeLayer = root.append("g");
    const nodeLayer = root.append("g");
    const labelLayer = root.append("g");

    svg.call(
      d3.zoom()
        .scaleExtent([0.25, 4])
        .on("zoom", (event) => {
          root.attr("transform", event.transform);
        })
    );

    const link = edgeLayer.selectAll("line")
      .data(DATA.edges)
      .enter()
      .append("line")
      .attr("class", "edge")
      .attr("marker-end", "url(#arrow-default)");

    const node = nodeLayer.selectAll("circle")
      .data(DATA.nodes)
      .enter()
      .append("circle")
      .attr("class", "node")
      .attr("r", (d) => d.radius)
      .on("click", (event, d) => {
        event.stopPropagation();
        selectedId = d.id;
        renderSelection();
        updateStyles();
      })
      .call(
        d3.drag()
          .on("start", dragStarted)
          .on("drag", dragged)
          .on("end", dragEnded)
      );

    const label = labelLayer.selectAll("text")
      .data(DATA.nodes)
      .enter()
      .append("text")
      .attr("class", "label")
      .text((d) => d.id);

    const simulation = d3.forceSimulation(DATA.nodes)
      .force("link", d3.forceLink(DATA.edges).id((d) => d.id).distance(120).strength(0.5))
      .force("charge", d3.forceManyBody().strength(-460))
      .force("center", d3.forceCenter(width / 2, height / 2))
      .force("collision", d3.forceCollide().radius((d) => d.radius + 24))
      .alpha(1)
      .alphaDecay(0.025)
      .on("tick", ticked);

    let selectedId = null;

    function edgeSourceId(edge) {
      return typeof edge.source === "string" ? edge.source : edge.source.id;
    }

    function edgeTargetId(edge) {
      return typeof edge.target === "string" ? edge.target : edge.target.id;
    }

    function ticked() {
      link
        .attr("x1", (d) => d.source.x)
        .attr("y1", (d) => d.source.y)
        .attr("x2", (d) => d.target.x)
        .attr("y2", (d) => d.target.y);

      node
        .attr("cx", (d) => d.x)
        .attr("cy", (d) => d.y);

      label
        .attr("x", (d) => d.x + d.radius + 6)
        .attr("y", (d) => d.y + 4);
    }

    function dragStarted(event, d) {
      if (!event.active) simulation.alphaTarget(0.24).restart();
      d.fx = d.x;
      d.fy = d.y;
    }

    function dragged(event, d) {
      d.fx = event.x;
      d.fy = event.y;
    }

    function dragEnded(event, d) {
      if (!event.active) simulation.alphaTarget(0);
      d.fx = null;
      d.fy = null;
    }

    function renderList(element, values) {
      element.innerHTML = "";
      if (!values.length) {
        const empty = document.createElement("div");
        empty.className = "empty";
        empty.textContent = "None";
        element.appendChild(empty);
        return;
      }

      const list = document.createElement("ul");
      values.forEach((value) => {
        const item = document.createElement("li");
        item.textContent = value;
        list.appendChild(item);
      });
      element.appendChild(list);
    }

    function renderSelection() {
      if (!selectedId) {
        nodeMetaEl.textContent = "Click a node to inspect its call relationships.";
        renderList(callsToEl, []);
        renderList(callsFromEl, []);
        return;
      }

      const selected = DATA.nodes.find((node) => node.id === selectedId);
      if (!selected) {
        selectedId = null;
        renderSelection();
        return;
      }

      nodeMetaEl.textContent = selected.id + "\n" + selected.file + ":" + selected.line;
      renderList(callsToEl, [...(outgoing.get(selected.id) || [])].sort());
      renderList(callsFromEl, [...(incoming.get(selected.id) || [])].sort());
    }

    function updateStyles() {
      const query = searchEl.value.trim().toLowerCase();
      const matches = new Set(
        DATA.nodes
          .filter((d) => !query || d.id.toLowerCase().includes(query) || d.file.toLowerCase().includes(query))
          .map((d) => d.id)
      );
      const selectedOutgoing = new Set(selectedId ? (outgoing.get(selectedId) || []) : []);
      const selectedIncoming = new Set(selectedId ? (incoming.get(selectedId) || []) : []);

      const connectedToSelected = new Set();
      if (selectedId) {
        (outgoing.get(selectedId) || []).forEach(id => connectedToSelected.add(id));
        (incoming.get(selectedId) || []).forEach(id => connectedToSelected.add(id));
        connectedToSelected.add(selectedId);
      }

      node
        .classed("selected", (d) => d.id === selectedId)
        .classed("forbidden", (d) => !!d.forbidden)
        .classed("external", (d) => !d.forbidden && !d.isUserFunction)
        .classed("match", (d) => !!query && matches.has(d.id))
        .style("opacity", (d) => {
          if (query && matches.has(d.id)) return 1;
          if (!selectedId) return 1;
          return connectedToSelected.has(d.id) ? 1 : 0.04;
        });

      label.style("opacity", (d) => {
        if (query && matches.has(d.id)) return 0.95;
        if (!selectedId) return 0.95;
        return connectedToSelected.has(d.id) ? 0.95 : 0.04;
      });

      link
        .style("stroke", (d) => {
          const sourceId = edgeSourceId(d);
          const targetId = edgeTargetId(d);
          if (selectedId && sourceId === selectedId) return OUTGOING_EDGE_COLOR;
          if (selectedId && targetId === selectedId) return INCOMING_EDGE_COLOR;
          return DEFAULT_EDGE_COLOR;
        })
        .style("opacity", (d) => {
          const sourceId = edgeSourceId(d);
          const targetId = edgeTargetId(d);
          if (!selectedId) return DEFAULT_EDGE_OPACITY;
          const isOutgoing = sourceId === selectedId && (outgoing.get(selectedId) || []).includes(targetId);
          const isIncoming = targetId === selectedId && (incoming.get(selectedId) || []).includes(sourceId);
          if (isOutgoing || isIncoming) return 0.9;
          return 0.04;
        })
        .attr("marker-end", (d) => {
          const sourceId = edgeSourceId(d);
          const targetId = edgeTargetId(d);
          if (selectedId && sourceId === selectedId && selectedOutgoing.has(targetId)) return "url(#arrow-outgoing)";
          if (selectedId && targetId === selectedId && selectedIncoming.has(sourceId)) return "url(#arrow-incoming)";
          return "url(#arrow-default)";
        });
    }

    searchEl.addEventListener("input", updateStyles);

    svg.on("click", () => {
      selectedId = null;
      renderSelection();
      updateStyles();
    });

    window.addEventListener("resize", () => {
      simulation.force("center", d3.forceCenter(window.innerWidth / 2, window.innerHeight / 2));
      simulation.alpha(0.3).restart();
    });

    renderSelection();
    updateStyles();
  </script>
</body>
</html>
EOF

    echo -ne "\n${BLUE}Call graph generated successfully in: ${YELLOW}$graph_file${NC}\n"
}

generate_graph_report() {
    generate_callgraph_report
}
