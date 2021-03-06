import ../sam

type
  Status = enum
    done, wontfix, inprogress

  Task = object
    id: int
    c: char
    title: string
    done: Status
    notes: string
    tags: array[0..1, string]
    user: User
    categories: seq[string]
    published: bool
    watchers: seq[User]
    points: array[0..4, int]
    completed: bool

  User = object
    name: string
    age: int
    point: float

var
  u1, u2: User
  t1, t2: Task

u1.name = "John Doe"
u1.age = 32
u1.point = 67.76
u2.name = "Mr. Bean"
u2.age = 65
u2.point = 53.1

t1.id = 1
t1.c = '$'
t1.title = "Blah blah"
t1.done = wontfix
t1.tags = ["test", "blah"]
t1.categories = @["works", "urgent"]
t1.user = u1
t1.published = true
t1.points = [5,6,7,8,9]
t1.watchers = @[u1, u2]
t1.completed = true

var js = $$t1
echo js
t2.loads(js)
echo $$t2
assert $$t2 == js
