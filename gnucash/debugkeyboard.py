# The contents of this file are copied entirely from public sources on the internet.

import code, sys, traceback
def DebugKeyboard(banner=""):

    # use exception trick to pick up the current frame
    try:
        raise None
    except:
        frame = sys.exc_info()[2].tb_frame.f_back

    # evaluate commands in current namespace
    namespace = frame.f_globals.copy()
    namespace.update(frame.f_locals)

    code.interact(banner=traceback.format_stack(frame,1)[0].split('\n')[0], local=namespace)
