import sam

type Node = ref object
  active: bool
  kind: string
  name: string
  id: int
  kids: seq[Node]

let json = """{"active":true,"kind":"NODE","name":"node0","id":0,"kids":[{"active":true,"kind":"NODE","name":"node1","id":1,"kids":[]},{"active":true,"kind":"NODE","name":"node2","id":2,"kids":[]},{"active":true,"kind":"NODE","name":"node3","id":3,"kids":[]},{"active":true,"kind":"NODE","name":"node4","id":4,"kids":[]},null,null,null]}"""

var node: Node = Node()
node.loads(json)