## Steps

- create an object similar to a Doc (core/doc/init.lua) but not tied to a file.
  We may call it InputDoc.
- use DocView(s) (defined in core/docview.lua) but tied to an InputDoc instead
  of to a Doc. To make this work InputDoc should implement the same methods
  and behave in the same way.
- create a new object derived by View to "assemble" several InputDoc(s).
  The InputDoc(s) should corresponds to the input and output snippet of the
  REPL.
  We may call this view ReplView.
  The ReplView should draw its InputDoc(s) with some spacing and displatch
  text input events mouve movements etc.
  It could be similar to RootView.
