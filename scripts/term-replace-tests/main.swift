import Foundation

var failures = 0
func check(_ name: String, _ got: String, _ want: String) {
    let ok = got == want
    if !ok { failures += 1 }
    print("\(ok ? "ok  " : "FAIL") \(name)" + (ok ? "" : "\n  got  \(got)\n  want \(want)"))
}
func r(_ find: String, _ replace: String, matchCase: Bool = true) -> TermRule {
    TermRule(find: find, replace: replace, matchCase: matchCase)
}

check("plain word", TermReplacer.apply([r("Lin Fen", "Lin Feng")], toHTML: "<p>Lin Fen smiled.</p>"),
      "<p>Lin Feng smiled.</p>")
check("whole word only", TermReplacer.apply([r("Li", "Lee")], toHTML: "<p>Like Li said, Lime.</p>"),
      "<p>Like Lee said, Lime.</p>")
check("possessive still a word edge", TermReplacer.apply([r("Li", "Lee")], toHTML: "<p>Li's sword</p>"),
      "<p>Lee's sword</p>")
check("longest first", TermReplacer.apply([r("Lin", "X"), r("Lin Feng", "Ling Feng")], toHTML: "<p>Lin Feng met Lin.</p>"),
      "<p>Ling Feng met X.</p>")
check("no chaining", TermReplacer.apply([r("A", "B"), r("B", "C")], toText: "A B"), "B C")
check("tags and attributes untouched",
      TermReplacer.apply([r("title", "name")], toHTML: "<p title=\"title\">a title</p>"),
      "<p title=\"title\">a name</p>")
check("script untouched",
      TermReplacer.apply([r("Qi", "Ki")], toHTML: "<script>var Qi = 1;</script><p>Qi flows</p>"),
      "<script>var Qi = 1;</script><p>Ki flows</p>")
check("match case on", TermReplacer.apply([r("Young Master", "young master")], toHTML: "<p>the young Master</p>"),
      "<p>the young Master</p>")
check("match case off", TermReplacer.apply([r("young master", "Young Master", matchCase: false)], toHTML: "<p>YOUNG MASTER!</p>"),
      "<p>Young Master!</p>")
check("replacement is escaped", TermReplacer.apply([r("and", "<&>")], toHTML: "<p>you and me</p>"),
      "<p>you &lt;&amp;&gt; me</p>")
check("Chinese term inside text", TermReplacer.apply([r("林峰", "Lin Feng")], toText: "我是林峰的朋友"), "我是Lin Feng的朋友")
check("Korean name with particle", TermReplacer.apply([r("김철수", "Kim")], toText: "김철수는 웃었다"), "Kim는 웃었다")
check("empty and duplicate rules ignored",
      TermReplacer.apply([r("  ", "x"), r("cat", "dog"), r("Cat", "bird")], toText: "cat"), "dog")
check("regex characters are literal", TermReplacer.apply([r("(Ch. 5)", "")], toText: "End (Ch. 5) here"), "End  here")
check("translator note removed", TermReplacer.apply([r("[TL note: lol]", "")], toHTML: "<p>Go.[TL note: lol]</p>"),
      "<p>Go.</p>")
check("text across lines + entities kept", TermReplacer.apply([r("Senior", "Elder")], toHTML: "<p>&quot;Senior,\nwait&quot;</p>"),
      "<p>&quot;Elder,\nwait&quot;</p>")
check("unclosed tag at end", TermReplacer.apply([r("a", "b")], toHTML: "a <p"), "b <p")
check("no rules = same", TermReplacer.apply([], toHTML: "<p>x</p>"), "<p>x</p>")

print(failures == 0 ? "all passed" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)
