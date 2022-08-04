# Factorio-A-Robot-Friend


A robot friend to serve you.



Features
-----------

A robot friend to serve you. It can currently do only limited tasks as an Alpha release.

Design and usage concepts:

- Players can select jobs that they want robots to do, i.e. build everything in a selected area. A job internally contains multiple tasks.
- Multiple robots can be assigned to do the same job. In some cases they would share the workload (i.e. building ghosts in an area), in other cases they would each complete the task individually (walking to a location).
- Any robots working on a job would carry out all tasks making up the job autonomously, in the example of building everything in a selected area, they would:  go and collect the resources needed from your base and then proceed to build everything for you. Automatically discovering, obtaining and crafting the items needed and moving around the map.
- Jobs and robots have a single master that they only obey, however, you can send your robot to work on other players jobs (if they allow it).
- Jobs will have behaviours you can set to affect your robots approach to the tasks, i.e. when moving is involved blocking certain transport modes (walking, driving a car, using a train).