# Heighliner

Heighliner is a general REST API and supervisor I wrote to serve as the front end for my personal projects like beacon, stellartel, and others.
The purpose was to consolidate these projects so that the network boundary is limited and resources are use more efficiently while avoiding some of the pain points in other architectural models.

Heighliner is written in elixir and leverages the BEAM VM's concurrency and fault-tolerance to support these goals.

Each `/lib` folder will come with a README describing it's responsibilities and relevant architecture.
