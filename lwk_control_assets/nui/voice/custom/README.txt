Your own dispatcher lines for callouts. Put call_<name>_1.ogg here (more variants as _2, _3...). In the callout:
voice = 'custom/call_<name>'. Dispatch plays it, then "Your call is at" and the street.
Optional: call_<name>_to_1.ogg, the same line ending as it leads into the street ("...on the bridge, at"): then dispatch
says the street straight after it instead.
The setup keeps this folder when it updates [c3r_core].
