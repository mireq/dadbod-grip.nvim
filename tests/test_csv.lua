-- Quick CSV parser test
local db = require("dadbod-grip.db")

-- Test 1: multiline quoted field
local raw1 = 'id,label,body\n1,long_string,abc\n2,multiline,"Line one\nLine two\nLine three"\n3,injection,"Robert\'); DROP TABLE users;--"\n'
local r1 = db.parse_csv(raw1)
assert(#r1.columns == 3, "cols should be 3, got " .. #r1.columns)
assert(#r1.rows == 3, "rows should be 3, got " .. #r1.rows)
assert(r1.rows[1][1] == "1", "row1 id should be 1")
assert(r1.rows[2][1] == "2", "row2 id should be 2")
assert(r1.rows[2][3] == "Line one\nLine two\nLine three", "row2 body should have newlines")
assert(r1.rows[3][1] == "3", "row3 id should be 3")
print("PASS: multiline quoted fields")

-- Test 2: psql footer
local raw2 = "name,age\nAlice,30\nBob,25\n(2 rows)\n"
local r2 = db.parse_csv(raw2)
assert(#r2.rows == 2, "should skip footer, got " .. #r2.rows)
print("PASS: psql footer skip")

-- Test 3: empty input
local r3 = db.parse_csv("")
assert(#r3.columns == 0 and #r3.rows == 0)
print("PASS: empty input")

-- Test 4: escaped quotes
local raw4 = 'col\n"he said ""hello"""\n'
local r4 = db.parse_csv(raw4)
assert(r4.rows[1][1] == 'he said "hello"', "escaped quotes: got " .. r4.rows[1][1])
print("PASS: escaped quotes")

-- Test 5: trailing comma (empty last field)
local raw5 = "a,b,c\n1,2,\n"
local r5 = db.parse_csv(raw5)
assert(#r5.rows[1] == 3, "should have 3 fields")
assert(r5.rows[1][3] == "", "last field should be empty")
print("PASS: trailing empty field")

print("\nALL TESTS PASSED")
