import Foundation

// Port of Mihon's ChapterRecognitionTest.kt (Apache-2.0, mihonapp/mihon @446f6df), every case in its order,
// plus Yomi's own cases at the end (either list order, the single-name API). Run: ./run.sh

typealias N = ChapterRecognition.Numbering
var failures = 0
var checks = 0

func expect(_ test: String, _ got: Any, _ want: Any) {
    checks += 1
    guard String(describing: got) != String(describing: want) else { return }
    failures += 1
    print("FAIL \(test): got \(got), want \(want)")
}

/// Names listed from the most to the least recent, none with a number from the source.
func assertNumbers(_ test: String, _ title: String = "", _ expected: (String, N)...) {
    let got = ChapterRecognition.parseChapterNumbers(mangaTitle: title, names: expected.map(\.0),
                                                     sourceNumbers: expected.map { _ in -1 })
    expect(test, got, expected.map(\.1))
}

func n(_ v: String?, _ c: String?) -> N { N(volume: v, chapter: c) }

assertNumbers("Basic Ch prefix", "Mokushiroku Alice", ("Mokushiroku Alice Vol.1 Ch.4: Misrepresentation", n("1", "4")))
assertNumbers("Basic Ch prefix with space after period", "Mokushiroku Alice",
              ("Mokushiroku Alice Vol. 1 Ch. 4: Misrepresentation", n("1", "4")))
assertNumbers("Basic Ch prefix with decimal", "Mokushiroku Alice", ("Mokushiroku Alice Vol.1 Ch.4.1: Misrepresentation", n("1", "4.1")))
assertNumbers("Basic Ch prefix with decimal", "Mokushiroku Alice", ("Mokushiroku Alice Vol.1 Ch.4.4: Misrepresentation", n("1", "4.4")))
assertNumbers("Basic Ch prefix with alpha postfix", "Mokushiroku Alice", ("Mokushiroku Alice Vol.1 Ch.4.a: Misrepresentation", n("1", "4a")))
assertNumbers("Basic Ch prefix with alpha postfix", "Mokushiroku Alice", ("Mokushiroku Alice Vol.1 Ch.4.b: Misrepresentation", n("1", "4b")))
assertNumbers("Basic Ch prefix with alpha postfix", "Mokushiroku Alice",
              ("Mokushiroku Alice Vol.1 Ch.4.extra: Misrepresentation", n("1", "4.99")))
assertNumbers("Name containing one number", "Bleach", ("Bleach 567 Down With Snowwhite", n(nil, "567")))
assertNumbers("Name containing one number and decimal", "Bleach", ("Bleach 567.1 Down With Snowwhite", n(nil, "567.1")))
assertNumbers("Name containing one number and decimal", "Bleach", ("Bleach 567.4 Down With Snowwhite", n(nil, "567.4")))
assertNumbers("Name containing one number and alpha", "Bleach", ("Bleach 567.a Down With Snowwhite", n(nil, "567a")))
assertNumbers("Name containing one number and alpha", "Bleach", ("Bleach 567.b Down With Snowwhite", n(nil, "567b")))
assertNumbers("Name containing one number and alpha", "Bleach", ("Bleach 567.extra Down With Snowwhite", n(nil, "567.99")))
assertNumbers("Chapter containing manga title and number", "Solanin", ("Solanin 028 Vol. 2", n("2", "28")))
assertNumbers("Chapter containing manga title and number decimal", "Solanin", ("Solanin 028.1 Vol. 2", n("2", "28.1")))
assertNumbers("Chapter containing manga title and number decimal", "Solanin", ("Solanin 028.4 Vol. 2", n("2", "28.4")))
assertNumbers("Chapter containing manga title and number alpha", "Solanin", ("Solanin 028.a Vol. 2", n("2", "28a")))
assertNumbers("Chapter containing manga title and number alpha", "Solanin", ("Solanin 028.b Vol. 2", n("2", "28b")))
assertNumbers("Chapter containing manga title and number alpha", "Solanin", ("Solanin 028.extra Vol. 2", n("2", "28.99")))
assertNumbers("Extreme case", "Onepunch-Man", ("Onepunch-Man Punch Ver002 028", n(nil, "28")))
assertNumbers("Extreme case with decimal", "Onepunch-Man", ("Onepunch-Man Punch Ver002 028.1", n(nil, "28.1")))
assertNumbers("Extreme case with decimal", "Onepunch-Man", ("Onepunch-Man Punch Ver002 028.4", n(nil, "28.4")))
assertNumbers("Extreme case with alpha", "Onepunch-Man", ("Onepunch-Man Punch Ver002 028.a", n(nil, "28a")))
assertNumbers("Extreme case with alpha", "Onepunch-Man", ("Onepunch-Man Punch Ver002 028.b", n(nil, "28b")))
assertNumbers("Extreme case with alpha", "Onepunch-Man", ("Onepunch-Man Punch Ver002 028.extra", n(nil, "28.99")))
assertNumbers("Chapter containing dot v2", "random", ("Vol.1 Ch.5v.2: Alones", n("1", "5")))
assertNumbers("Number in manga title", "Ayame 14", ("Ayame 14 1 - The summer of 14", n(nil, "1")))
assertNumbers("Space between ch x", "Mokushiroku Alice", ("Mokushiroku Alice Vol.1 Ch. 4: Misrepresentation", n("1", "4")))
assertNumbers("Chapter title with ch substring", "Ayame 14", ("Vol.1 Ch.1: March 25 (First Day Cohabiting)", n("1", "1")))
assertNumbers("Chapter containing multiple zeros", "random", ("Vol.001 Ch.003: Kaguya Doesn't Know Much", n("1", "3")))
assertNumbers("Chapter with version before number", "Onepunch-Man",
              ("Onepunch-Man Punch Ver002 086 : Creeping Darkness [3]", n(nil, "86")))
assertNumbers("Version attached to chapter number", "Ansatsu Kyoushitsu",
              ("Ansatsu Kyoushitsu 011v002: Assembly Time", n(nil, "11")))
assertNumbers("Number after manga title with chapter in chapter title case", "Tokyo ESP",
              ("Tokyo ESP 027: Part 002: Chapter 001", n(nil, "27b")))
assertNumbers("Number after unwanted tag", "One-punch Man", ("Mag Version 195.5", n(nil, "195.5")))
assertNumbers("Unparseable chapter", "random", ("Foo", n(nil, nil)))
assertNumbers("Chapter with time in title", "random", ("Fairy Tail 404: 00:00", n(nil, "404")))
assertNumbers("Chapter with alpha without dot", "random", ("Asu No Yoichi 19a", n(nil, "19a")))
assertNumbers("Chapter title containing extra and vol", "Fairy Tail", ("Fairy Tail 404.extravol002", n(nil, "404.99")))
assertNumbers("Chapter title containing extra and vol", "Fairy Tail", ("Fairy Tail 404 extravol002", n(nil, "404.99")))
assertNumbers("Chapter title containing omake and vol", "Fairy Tail", ("Fairy Tail 404.omakevol002", n(nil, "404.98")))
assertNumbers("Chapter title containing omake and vol", "Fairy Tail", ("Fairy Tail 404 omakevol002", n(nil, "404.98")))
assertNumbers("Chapter title containing special and vol", "Fairy Tail", ("Fairy Tail 404.specialvol002", n(nil, "404.97")))
assertNumbers("Chapter title containing special and vol", "Fairy Tail", ("Fairy Tail 404 specialvol002", n(nil, "404.97")))
assertNumbers("Chapter title containing commas", "One Piece", ("One Piece 300,a", n(nil, "300a")))
assertNumbers("Chapter title containing commas", "One Piece", ("One Piece Ch,123,extra", n(nil, "123.99")))
assertNumbers("Chapter title containing commas", "One Piece", ("One Piece the sunny, goes swimming 024,005", n(nil, "24.005")))
assertNumbers("Chapter title containing hyphens", "Solo Leveling", ("ch 122-a", n(nil, "122a")))
assertNumbers("Chapter title containing hyphens", "Solo Leveling", ("Solo Leveling Ch.123-extra", n(nil, "123.99")))
assertNumbers("Chapter title containing hyphens", "Solo Leveling", ("Solo Leveling, 024-005", n(nil, "24.005")))
assertNumbers("Chapter title containing hyphens", "Solo Leveling", ("Ch.191-200 Read Online", n(nil, "191.2")))
assertNumbers("Chapters containing season", "D.I.C.E", ("D.I.C.E[Season 001] Ep. 007", n("1", "7")))
assertNumbers("Chapters in format sx - chapter xx", "The Gamer", ("S3 - Chapter 20", n("3", "20")))
assertNumbers("Chapters ending with s", "One Outs", ("One Outs 001", n(nil, "1")))
let sister = "The Sister of the Woods with a Thousand Young"
assertNumbers("Chapters containing ordinals", sister, ("The 1st Night", n(nil, "1")))
assertNumbers("Chapters containing ordinals", sister, ("The 2nd Night", n(nil, "2")))
assertNumbers("Chapters containing ordinals", sister, ("The 3rd Night", n(nil, "3")))
assertNumbers("Chapters containing ordinals", sister, ("The 4th Night", n(nil, "4")))
assertNumbers("Parts are letters", "", ("Chapter 1.5 Part I", n(nil, "1.5a")))
assertNumbers("Parts are letters", "", ("Chapter 1.5 Part II", n(nil, "1.5b")))
assertNumbers("Parts are letters", "", ("Chapter 12 Part 3", n(nil, "12c")))
assertNumbers("Parts are letters", "", ("Vol.2 Chapter 7 - Part IV", n("2", "7d")))
assertNumbers("Parts are letters", "", ("Part 3", n(nil, "3")))

for (s, d) in [("12", 12.0), ("10.5", 10.5), ("19a", 19.1), ("19i", 19.9), ("1.5a", 1.5), ("-2", -2.0)] {
    expect("Numbers are turned into doubles \(s)", ChapterRecognition.toDouble(s), d)
}

assertNumbers("Volume is not taken as the chapter number", "Mokushiroku Alice", ("Mokushiroku Alice Vol.3", n("3", nil)))
assertNumbers("Volume is not taken as the chapter number", "Mokushiroku Alice", ("Vol.3 12", n("3", "12")))
assertNumbers("Seasons are volumes", "", ("Vol-3 Chapter 2", n("3", "2")))
assertNumbers("Seasons are volumes", "", ("Mob's 100", n(nil, "100")))
assertNumbers("Volumes are only taken from the name", "",
              ("Vol.2 Ch.5", n("2", "5")), ("Ch.4", n(nil, "4")), ("Vol.2 Ch.3", n("2", "3")))
assertNumbers("Numbers every similar name shares are ignored", "",
              ("Group 2 Chapter 387", n(nil, "387")), ("Group 2 Chapter 386", n(nil, "386")),
              ("Group 2 Chapter 385", n(nil, "385")))
assertNumbers("Shared numbers after a chapter prefix are kept", "",
              ("Chapter 5 Part 3", n(nil, "5c")), ("Chapter 5 Part 2", n(nil, "5b")), ("Chapter 5 Part 1", n(nil, "5a")))
assertNumbers("Chapters without a number fill the missing whole numbers", "",
              ("Chapter 4", n(nil, "4")), ("The Return", n(nil, "3")), ("Chapter 2", n(nil, "2")))
assertNumbers("Chapters without a number fill the missing whole numbers", "",
              ("Chapter 5", n(nil, "5")), ("Rain", n(nil, "4")), ("Snow", n(nil, "3")), ("Chapter 2", n(nil, "2")))
assertNumbers("Chapters without a number go between", "",
              ("Chapter 11", n(nil, "11")), ("Bonus: Beach Episode", n(nil, "10.5")), ("Chapter 10", n(nil, "10")))
assertNumbers("Chapters without a number go between", "",
              ("Chapter 13", n(nil, "13")), ("Intermission", n(nil, "10.5")), ("Chapter 10", n(nil, "10")))
assertNumbers("Chapters without a number go between", "",
              ("Chapter 11", n(nil, "11")), ("Rain", n(nil, "10.6")), ("Snow", n(nil, "10.5")), ("Chapter 10", n(nil, "10")))
assertNumbers("Chapters without a number go between", "",
              ("Chapter 4", n(nil, "4")), ("Side Story", n(nil, "2.5")), ("Chapter 2", n(nil, "2")))
assertNumbers("Chapters without a number go between", "",
              ("Chapter 3", n(nil, "3")), ("Extra", n(nil, "2.6")), ("Chapter 2.5", n(nil, "2.5")))
assertNumbers("Chapters without a number go between", "",
              ("Chapter 3", n(nil, "3")), ("Extra", n(nil, "2.95")), ("Chapter 2.9", n(nil, "2.9")))
assertNumbers("Chapters without a number at the ends", "", ("Afterword", n(nil, "100.5")), ("Chapter 100", n(nil, "100")))
assertNumbers("Chapters without a number at the ends", "",
              ("Hiatus Announcement", n(nil, nil)), ("Chapter 100", n(nil, "100")))
assertNumbers("Chapters without a number at the ends", "", ("Chapter 1", n(nil, "1")), ("Prologue", n(nil, "0")))
assertNumbers("Chapters without a number at the ends", "", ("Chapter 1", n(nil, "1")), ("Character Profiles", n(nil, nil)))
assertNumbers("A prologue before chapters in volumes is in volume 0", "",
              ("Vol.1 Ch.1", n("1", "1")), ("Prologue", n("0", "0")))
assertNumbers("A prologue before chapters in volumes is in volume 0", "",
              ("Vol.1 Ch.1", n("1", "1")), ("Vol.2 Prologue", n("2", "0")))
assertNumbers("Only numbered within a volume", "",
              ("Vol.1 Ch.3", n("1", "3")), ("Rain", n(nil, "2")), ("Vol.1 Ch.1", n("1", "1")))
assertNumbers("Only numbered within a volume", "",
              ("Vol.2 Ch.3", n("2", "3")), ("Rain", n(nil, nil)), ("Vol.1 Ch.1", n("1", "1")))
assertNumbers("Only numbered within a volume", "",
              ("Vol.2 Ch.3", n("2", "3")), ("Vol.2 Rain", n("2", nil)), ("Ch.1", n(nil, "1")))
assertNumbers("Only numbered within a volume", "",
              ("Vol.2 Ch.3", n("2", "3")), ("Vol.1 Rain", n("1", nil)), ("Vol.2 Ch.1", n("2", "1")))
assertNumbers("Only numbered within a volume", "", ("Extra", n(nil, "10.5")), ("Vol.2 Ch.10", n("2", "10")))
assertNumbers("Only numbered within a volume", "", ("Vol.2 Extra", n("2", "10.5")), ("Vol.2 Ch.10", n("2", "10")))
assertNumbers("Only numbered within a volume", "", ("Vol.3 Extra", n("3", nil)), ("Vol.2 Ch.10", n("2", "10")))
expect("Numbers from the source are kept",
       ChapterRecognition.parseChapterNumbers(mangaTitle: "", names: ["Vol.1 Chapter 3", "Chapter 2"], sourceNumbers: [7, -1]),
       [n("1", "7"), n(nil, "2")])

// MARK: - Yomi

expect("Yomi: newest first", ChapterRecognition.numbers(mangaTitle: "", names: ["Chapter 4", "The Return", "Chapter 2"],
                                                        sourceNumbers: [nil, nil, nil]).description,
       [4.0, 3.0, 2.0].map(Optional.some).description)
expect("Yomi: oldest first is read reversed",
       ChapterRecognition.numbers(mangaTitle: "", names: ["Chapter 2", "The Return", "Chapter 4"],
                                  sourceNumbers: [nil, nil, nil]).description,
       [2.0, 3.0, 4.0].map(Optional.some).description)
expect("Yomi: prologue oldest first",
       ChapterRecognition.numbers(mangaTitle: "", names: ["Prologue", "Chapter 1", "Chapter 2"],
                                  sourceNumbers: [-1, -1, -1]).description,
       [0.0, 1.0, 2.0].map(Optional.some).description)
expect("Yomi: unknown stays nil",
       ChapterRecognition.numbers(mangaTitle: "", names: ["Hiatus Announcement", "Chapter 100"],
                                  sourceNumbers: [nil, nil]).description,
       [nil, Optional(100.0)].description)
expect("Yomi: single-name API", ChapterRecognition.number(mangaTitle: "Solanin", chapterName: "Solanin 028 Vol. 2",
                                                          sourceNumber: -1).debugDescription,
       Optional(28.0).debugDescription)
expect("Yomi: single-name keeps source number", ChapterRecognition.parseChapterNumber(
    mangaTitle: "", chapterName: "Chapter 3", chapterNumber: 7), 7.0)

print(failures == 0 ? "OK \(checks) checks" : "\(failures) of \(checks) checks FAILED")
exit(failures == 0 ? 0 : 1)
