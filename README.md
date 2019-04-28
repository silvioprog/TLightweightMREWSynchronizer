# TLightweightMREWSynchronizer

[`TLightweightMREWSynchronizer`](https://github.com/silvioprog/TLightweightMREWSynchronizer/blob/master/Source/LightweightMREWSynchronizer.pas) allows multiple threads to read from the protected memory simultaneously, while ensuring that any thread writing to the memory has exclusive access.

# Temporary repo

This class/repo is just a study I'm doing to solve a deadlock problem I've got in threaded commercial project I work on. I know [`TMultiReadExclusiveWriteSynchronizer`](http://docwiki.embarcadero.com/Libraries/Rio/en/System.SysUtils.TMultiReadExclusiveWriteSynchronizer) and I would like to use it, however, I was frustrated to experience its slowness when comparing it to a common [`TCriticalSection`](http://docwiki.embarcadero.com/Libraries/Rio/en/System.SyncObjs.TCriticalSection).
