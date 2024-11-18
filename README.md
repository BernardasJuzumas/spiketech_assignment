# Widgets inc. API service

## How to run
### Local deployment

**Using docker-compose**
1. Navigate to `deployments/docker-compose`:
```shell
> cd deployments/docker-compose
> docker-compose up --build -d
```

2. Localhost leads to OpenAPI specification of the api. All the api function calls are available through /rpc/{function name} path. The paths available will be listed in the spec:
 - `rpc/add_widget` endpoint accepts `{"widget_sn": "widget's serial number","name":"widget's name", "slots":[]}` payloads.
 - `rpc/remove_widget` endpoint accepts `{"widget_sn": "widget's serial number"}`
 - `rpc/associate_widgets` endpoint accepts `{"widget1_sn": "sn", "widget2_sn": "sn2", "port":"port type"}`
 - `rpc/remove_association` endpoint accepts `{"widget1_sn": "sn", "widget2_sn": "sn2", "port":"port type"}`

3. All endpoints produce OK (HTTP/1.1 204 No Content) response if successful or a payload with an exception if they are not.

OK:
```shell
$ curl "http://localhost/rpc/add_widget" -i\
  -X POST -H "Content-Type: application/json" \
  -d '{ "widget_sn": "F", "widget_name": "A", "slots":["P","R","R"]}'
HTTP/1.1 204 No Content
Server: nginx/1.27.2
Date: Sat, 16 Nov 2024 19:06:33 GMT
Connection: keep-alive
Content-Range: 0-0/*
```

Conflict:
```shell
$ curl "http://localhost/rpc/add_widget" -i\
  -X POST -H "Content-Type: application/json" \
  -d '{ "widget_sn": "E", "widget_name": "A", "slots":["P","R","R"]}'
HTTP/1.1 409 Conflict
Server: nginx/1.27.2
Date: Sat, 16 Nov 2024 19:06:09 GMT
Content-Type: application/json; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive

{"code":"23505","details":"Key (serial_number)=(E) already exists.","hint":null,"message":"duplicate key value violates unique constraint \"widgets_serial_number_key\""}%
```

4. In `docker-compose.yml` I added a container with small go program to load test the environment. To use it launch docker compose with the following settings:
```bash
env GO_LOADER_REPLICAS=1 docker compose up --build -d
```
(you can increase a number of replicas at your own peril, my oldie M1 Air is throttling)

The results are stored in victoria-metrics database, assuming the same setup (localhost), the [live report can be accessed here](http://localhost:8428/vmui/#/?g0.range_input=5m&g0.end_input=2024-11-18T10%3A01%3A12&g0.relative_time=last_5_minutes&g0.tab=0&g0.expr=count_over_time%28request_times%5B1s%5D%29&g1.range_input=5m&g1.end_input=2024-11-18T10%3A01%3A12&g1.relative_time=last_5_minutes&g1.tab=0&g1.expr=avg_over_time%28request_times%5B1s%5D%29*10000&g0.step_input=1s&g1.step_input=1s)
> *Note: I have adjusted the scale of response times for better visibility (multiplied by 10000) as they are mostly sub-20ms each*

5. Initial performance measurements (as shown in the image below) show positive results.

![Load test performance measurements. Red - request count per 5s. Green - average response time in seconds. Blue - mean response time in seconds. Purple - inversed MAX response time in seconds. All time values are multiplied by 10000 for measurements to be visible.](images/perf.png)

Lines:
 - Red - request count per 5s. 
 - Green - average response time in seconds. 
 - Blue - mean response time in seconds. 
 - Purple - inversed MAX response time in seconds. All times are multiplied by 10000 for measurements to be visible.
All times values are multiplied by 10000 for measurements to be visible.
Interval is 5s per point, to have a bit less variation.

**Important factor** is that my development machine is actively throttling at more heavy workloads. For this I have an inversed purple line that correlates with the amount of requests sent. It indicates the throttling happening in the background which distorts the testing data a little.

Even despite the throttling it is visible that the baseline (green and blue lines) is barely impacted by the amount of requests the system is handling. The next step is to do a full load test on a sufficient hardware. Perhaps expand testing to more operations that simple join-writes.

## Assignment

**Mission:**
Design, build and deploy a high throughput **service** for handling **widgets**

**Service description:**
- Service allows creating, removing and associating **widgets** via API
- Service must be capable of handling *thousands* of requests without noticeable latency
- Service operations are singular. Service does not support batched transactions.

**Widgets description:**
- Every **widget** is defined a set of **serial number**, **name** and **ports** that the widget will use to associate with other widgets
- **Serial number** is a unique text value. There cannot be two widgets with the same value.
- **Name** is not unique. There can be widgets with the same name.
- **Ports** can only belong to specific **port type**.
- There are three supported **port types**: "P", "R" and "Q".
- Not all widgets support all **port types**. 
- A widget can have more than one port of the same type.
- A widget can have 3 ports at most. I will refer to the as **port slots**.
- Every widget is created with a predetermined number of ports slots of specific port type. *For example: QQ, P, PRR*.
- Widgets can be **associated** using the same port of each widget.
- The association is bi-directional, meaning once associated each widget utilize a port of the same type.
- Two widgets can be associated more than once, but not on the same port type.

## Solution - high level

### Numbers and constraints

- **Must handle up to 10k requests per second** - "*Thousands*"
- **10 million widgets** 
- **20 million slots** (*approx 2 slots per widget*).
- **Widgets -> slots relationships**
- **Concurrent operations**, avoid race conditions.
- **Non degrading performance under heavy load**

### Keep it simple

Since there's not much time (as always), the major additional criteria is keeping it smart and simple. As with any problem there are many complex solutions all with their pros and cons and I am happy to discuss them in detail. But for now..
### High level components

- **Database** - I chose **PostgreSQL**. It scales up well, handles a lot of data and there are plenty cost-effective managed hosting solutions, even platforms for simple deployment. On the functional part it will provide row-level-locking which will help avoid potential race conditions when associating widgets (more on that in Implementation part)
- **API middleware** - to abstract direct database implementation and provide an API interface I chose **PostgREST** - a standalone web server that serves a simple RESTful API to PostgreSQL. Major benefit of this solution is having a single source of truth, keeping all application logic in database and avoiding opinionated implementations. Furthermore PostgREST is well optimized for this task, uses modern interfacing techniques (like dynamic connection pooling) and can reportedly handle up to 2000 requests/sec on low configuration machines.
- **Load balancer** - to distribute the load the load balance will be used. The app will also "hide" behind it, not exposing its internal resources, making **load balancer the primary interface to application**.

### Interfaces

The service will provide following interfaces to facilitate the required functionality:
- **`add_widget`**: creates a new widget when `serial number`, `name` and `port slots` are supplied. 
- **`remove_widget`**: allows removing a widget with a supplied `serial number`. It is implied that removal of the widget "disconnects" it from other widgets and frees up their port slots for further association.
- **`associate_widgets`**: takes in serial numbers of two `widgets` and a `port` and creates and association between them, given both widgets posses a `slot` of provided port type.
- **`remove_association`**: takes in same parameters as above, but instead of creating - removes the existing association between two widgets if one exists.

### Testing

Testing to be done in:
- Database layer - scripts testing against business logic and database performance to be developed.
- Integration layer - Businees logic: do all operations work as expected? Performance: how many requests and on what configuration machines can PostgREST handle.
- Infrastructure layer - how infrastructure reacts under load. How fast are new resources provisioned when needed.

## Implementation

### Database

#### Schema, Tables, types and indexes

[SQL for creating schema, type, tables and indexes is here](sql/1.widgets-create-tables-types-indexes.sql)

**Schema:**
Reserving dedicated namespace `widgets`.

**Type:**

The enum `port_type` will allow to conveniently enforce only the allowed ports.

**Tables:**

Widgets will be held separately from their slots. `Widgets` table will create the relation between their serial number and their key, while `slots` will hold every slot of a widget and it's possbile association. 

This way the operations for associating slots will be much faster and this allows of utilizing SQL basic features like enforcing constrants (widget can't associate to itself) cascading updates (when widget is deleted it's slots get deleted too, and the associations become NULL).

A side effect of this decision is that when creating an association there will have to be 2 inserts: 1 in the associating table and one in the receiving one. This is solved with SQL transactional logic, defined in 'Functions' paragraph ahead.

**Indexes:**

Partial index `idx_unique_widget_slot_assoc_except_null_assoc` enforces the rule that only one association on the same port can be established while allowing there to be multiple NULL associations (widget can have multiple free slots of the same port type)

Global index `idx_slots_widget_slot_assoc` indexes of the whole set of slots values for fast selects. Since this will be a B-Tree this index will be relatively small.

Finally there will be many requests referencing witdget's serial number. `idx_widgets_serial_number` is the largest index, because it will contain values of type TEXT.

**Why no partitions?**

Since widgets table must ensure uniqueness of serial number and id separately there is no way to effciently split the table in to partitons. Slots don't have clear unique constraints either and their indexes already serve as (sort of) maximum possible partitions (with NULL associations and full tree). 
Even though partitoning would help parallelize the work, creating a schema that would allow utilizing partitions seems less efficient at a glance. This is definitely in my mind for future, but let's get on with the rest of the solution.

#### Functions
All functions are defined with admin privileges (the definer role must be administrative) so only permissions to these functions and not the affected tables and operations need to be granted to execute them. This is common security practice that will come in handy when connecting to API middleware.

[Add_widget (serial number, name, port slots)](sql/2.widgets-function-add_widget.sql)
This function adds a widget and creates relevant ports, and returns success message or throws error if duplicate entry exists. It expects widgets serial number and name as text value, and a list of supported ports as an array.

[Associate_widgets(widget serial number, another widget's serial number, port)](sql/3.widgets-function_associate_widgets.sql)
This function checks that both referenced widgets exist, that both have an open port slot of the defined type and then associates both widgets by 
getting setting their id's in each others association field.
The complexity here is that because I am avoiding additional id index on slots table I had to use cursors to target and lock specific rows for update. Otherwise there is a possibility to update more than one row. Functional, but a bit less readible.

[Remove_association(widget serial number, another widget's serial number, port)](sql/4.widgets-function_remove_association.sql)
Removes association between widgets. Ensures that both widgets exist, that association exists and then removes it.

[Remove_widget(widget serial number)](sql/5.widgets-function-remove_widget.sql)
Deletes a widget of a given serial number. The resulting row updates are cascading as per table column value restriction definitions explained earlier.

#### Users and Groups

Per best practices let's create two roles
 - `web-anon` to manage schema and method access
 - `authenticator` to manage authentication

 The `web-anon` will only have acces to execute the previously defined functions and will not be granted access to other methods and tables, allowing for fine-grained access control.

Web service will authenticate to service using `authenticator` credentials.

#### Testing database, quick benchmark

To be very honest writing proper tests is simply not in the cards time-wise. I test all functionality manually [HERE](sql/widgets-tests.sql), seems to work.

I wrote helper function [generate_random_widget](sql/widgets-function-generate_random_widget.sql) and a query [to generate test data](sql/widgets-generate-widgets.sql) to populate test data. Takes nearly 40 minutes to complete on my old m1 air which is a good sign, as 10mil transactions (every of which performs multiple scans on both tables/indexes) per 600 second = 4k+ transactions/s. Without optimizations or sufficient RAM to boot. On the other hand the script does not consider multiple managed connections, which may become a bottleneck if not handled with care.

(Note: in [test data generation script](sql/widgets-generate-widgets.sql)) I also provide a potentially faster approach to  generate test data (commented), that is using parallelization where the query is explicitly set to supress any messages and but this approach does not simmulate immediate database commits.

Lastly [a query to check our table index size](sql/widgets-generate-widgets.sql)) helps to determine the optimal memory resources to conveniently accomodate inxes in system RAM.

### Configuration

#### PostgreSQL

**Numbers**
1. Database needs to handle index size for defined workloads an a little extra. The total amount of indexes at 10 million widgets will be close to 2GB.
2. Database must support thousands of potential consecutive connections. Assuming we get up to 10k request per second, and every transaction takes up to 100ms (0.1s) to handle the database will need to potentially have up to 1000 open connection slots. Every connection takes up memory too (~1-2MB per connection). Supporting thousands of parallel connections will also contribute to CPU load. We will get inbuilt connection pooling support from PostgREST too, so this setting should satisfy the requirement.

> All the estimations provided below are just assumptions for "worst-case". With sufficient time and tuning these resources can be drastically scaled back

Although the service database is relatively small, transactions are few and optimized, to reach performace benchmarks I would start start with the following database server's hardware configuration:
- 4-8 vCPUs to handle burst-parallel workloads;
- At least 16GB of system memory to fit larger indexes and maintain connextion pools.
- SSD. The faster - the better. The below settings try to mitigate disk-write performace affecting the system operations as much as possible. (Note: with very fast SSDs it might be possible to forego the requirements, but usually using fast SSDs cost more than affordable RAM)

The followigh configuration values in `postgresql.conf` should compliment the above hardware configurations:

```conf
# Main settings to adjust
max_connections = 1000 # 10x higher than default
shared_buffers = 4GB # or 1/4th of system RAM.
maintenance_work_mem = 512MB # will help with vacuum operations
work_mem = 4MB # with 1000 consecutive connections this can multiply to 4GB
effective_cache_size = 10GB # set to 50-75% of total system memory, so lower if system is with lower ram.

# WRITE-AHEAD LOG
wal_buffers = 16MB	

# Autovacuum (garbage collection) settings. We can get in to details, but these setting will make it adjust to our index size and access frequency.
autovacuum_vacuum_scale_factor = 0.05 
autovacuum_analyze_scale_factor = 0.02
autovacuum_vacuum_threshold = 1000
autovacuum_analyze_threshold = 1000
```

#### PostgREST

PostgREST is quite performant. Two instances can fit on a single CPU core, handling approx 400 connections (it is advertised that on such instances it can do up to 2000). Since there will be up to 1000 connections - there's going to be a need for 3 of such instances. 2vCPUs + 3GB RAM total should satisfy this requirement.

Setting up postgrest instance acan be done via environment viariables, config files or (even!) from the database. For now I will setup `settings.conf`:

```conf
db-uri = "postgres://authenticator:mysecretpassword@localhost:5432/postgres" #the DB connection string
db-schemas = "widgets" # the schema in which our solution operates
db-anon-role = "web_anon" #this is the role we setup in our deployment file
#server-port = 3000 #default, in some configurations like kubernetes this is auto-managed
db-pool = 400 # !!!! Very important - this should be set as [1000 (max connections) / max instances of PostgREST]. Current configuration assumes we will be able to 'spin-up' up to 10 instances.
```

#### Load balancer

Load balancer should be setup to distribute the load evenly between available instances of PostgREST assuming deployment where there are many. The major concern is hits per second. For up to few thousand Nginx (or equivalent) running on a 2vCPUs should be sufficient.

## Deployment

This solution is relatively simple to deploy in various configurations. I will provide a few viable options in detail and discuss several alternatives afterwards.

### Local deployment

The solution can be deployed and tested locally using a [docker-compose file](deployments/docker-compose/docker-compose.yml)).

### Cloud-native (AWS)

(Note: although I'm using AWS as example, the same deployment can be done in any other major cloud service provider's infrastructure with only minor difference).

- The setup would to use managed DB - Aurora/RDS instance. Exact measurements should be done to find best price/performance ratio.
- PostgREST on ECS + autoscaling group.
- Amazon Load balancer.
- All components on VPS
- Credentials/settings shared via environment variables

This setup is mirroring the docker-compose configuration just in AWS.

### Kubernetes (managed or unmanaged)

It is also possible to manage this whole set-up in kubernetes abstractions. Possibility to be cloud-agnostic might be necesseray in certain scenarios. For now just recognizing another option in store, time-constraints are not in favor to build and test this.

## Considerations:

#### Performance

**Configure `postgresql.conf` for application workloads**

When manually hosting PostgreSQL the standard configuration is of a little good, some ideas to make it more performant:
```
# Memory settings considering server with 16GB total RAM
shared_buffers = 4GB # 1/4 of memory to store indexes (measured at ~2GB total)
maintenance_work_mem = 1GB # for frequent indexing and vacuuming big tables
effective_cache_size = 10GB # 50-75% of total system memory.
```

**Alternative to dynamic connection pooling - PgBouncer**

A common practice to deal with heavy, connection-intensive workloads for PostgreSQL is to use a separate service such as PgBouncer. It would stand between database and API middleware.  Considering current workloads it is still fine to use simple dynamic connection pooling, but additional scale may require more aggressive session management techniques.

#### Security

**HTTPS**

The PostgREST service does not implement HTTPS by default. Production-ready deployments will require setting up a reverse proxy to enable HTTPS between clients and service API.

**Authentication**

The current implementation does not take Authenticaition in to account. The real, production ready service might consider some authentication implementation.