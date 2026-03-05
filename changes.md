- Add spartan ultrascale+ family to supported families 
- When validating block design, i got the errors:
-----------------------------------------------------------
[Common 17-55] 'get_property' expects at least one object.
Resolution: If [get_<value>] was used to populate the object, check to make sure this command returns at least one valid object. 

[BD 41-1273] Error running propagate TCL procedure: ERROR: [Common 17-55] 'get_property' expects at least one object.
    ::OVGN_user_OpenHBMC_2.0::propagate Line 7
-------------------------------------------------------------------
When validating the design, the assigned address space for hyperram
got deleted automatically. Codex made some fixes to avoid that