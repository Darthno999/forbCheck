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
    perl - "$@" <<'PERL'
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

my %defs;
my @functions;
my %seen_name;
my %keywords = map { $_ => 1 } qw(if for while switch return sizeof case do else);

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

for my $func (@functions) {
    my $source = $func->{id};
    my $body = $func->{body};

    while ($body =~ /\b([A-Za-z_]\w*)\s*\(/g) {
        my $target = $1;
        next if !exists $defs{$target};
        next if $keywords{$target};
        next if $edges{$source}{$target};

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
      --text: #e0e0e0;
      --muted: #7f88a8;
      --edge: #4a4a6a;
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
    #info {
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
      color: var(--cyan);
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.08em;
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
      stroke-opacity: 0.55;
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
      stroke: var(--magenta);
      stroke-width: 2.4px;
      fill: rgba(255, 0, 170, 0.22);
      filter: url(#selected-glow);
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
      #info {
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
      <h3>Functions Called</h3>
      <div id="callsTo"></div>
      <h3>Functions Called By</h3>
      <div id="callsFrom"></div>
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
      .attr("id", "arrow")
      .attr("viewBox", "0 -5 10 10")
      .attr("refX", 18)
      .attr("refY", 0)
      .attr("markerWidth", 7)
      .attr("markerHeight", 7)
      .attr("orient", "auto")
      .append("path")
      .attr("fill", "#4a4a6a")
      .attr("fill-opacity", 0.75)
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
      .attr("marker-end", "url(#arrow)");

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

      node
        .classed("selected", (d) => d.id === selectedId)
        .classed("match", (d) => !!query && matches.has(d.id))
        .style("opacity", (d) => !query || matches.has(d.id) ? 1 : 0.14);

      label.style("opacity", (d) => !query || matches.has(d.id) ? 0.95 : 0.12);

      link.style("opacity", (d) => {
        if (!query) return 0.55;
        return matches.has(d.source.id) || matches.has(d.target.id) ? 0.72 : 0.06;
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
