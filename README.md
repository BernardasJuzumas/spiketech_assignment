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
- **Load balancer** - to distribute the load the load balance will be used. The solution considers several deployment approaches with different balancers in place.
### Interfaces

The service will provide following interfaces to facilitate the required functionality:
- **`add_widget`**: creates a new widget when `serial number`, `name` and `port slots` are supplied. 
- **`remove_widget`**: allows removing a widget with a supplied `serial number`. It is implied that removal of the widget "disconnects" it from other widgets and frees up their port slots for further association.
- **`associate_widgets`**: takes in serial numbers of two `widgets` and a `port` and creates and association between them, given both widgets posses a `slot` of provided port type.
- **`remove_association`**: takes in same parameters as above, but instead of creating - removes the existing association between two widgets if one exists.

### Testing

TBA :)

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

Since in current solution widgets table must ensure uniqueness of serial number and id separately there is no way to effciently split the table in to partitons. Slots don't have clear unique constraints either and their indexes already serve as maximum possible partitions. 
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

#### Testing database operations

To be very honest writing proper tests is simply not in the cards. I test all functionality manually [HERE](sql/widgets-tests.sql)

### Configuration
#### PostgREST

#### PostgreSQL
#### Docker and docker-compose



### Deployment: 
*Real men test in production*





There are many ways to deploy this solution, but it comes to 

Either host this in
The easiest and hassle-free approach would be to host the database solution in AWS, such as Aurora DB. Since our (royal us, or me in this case) is limited - will do a limited hosting option

### Considerations:

#### Deployment

The proposed solution uses a local deployment

#### Performance

**Configure `postgresql.conf` for application workloads**

When manually hosting PostgreSQL the standard configuration is of a little good, some ideas to make it more performant:
```
# Memory settings considering server with 16GB total RAM
shared_buffers = 4GB # 1/4 of RAM to store indexes (measured at ~2GB total)
maintenance_work_mem = 1GB # for frequent indexing and vacuuming big tables
effective_cache_size = 8GB
```

**Alternative to dynamic connection pooling - PgBouncer**

A common practice to deal with heavy, connection-intensive workloads for PostgreSQL is to use a separate service such as PgBouncer. It would stand between database and API middleware.  Considering our current workloads it is still fine to use simple dynamic connection pooling, but additional scale may require more aggressive session management techniques.

**Rate limiting**

#### Security

**HTTPS**

The PostgREST service does not implement HTTPS by default. Production-ready deployments will require setting up a reverse proxy to enable HTTPS between clients and service API.

**Authentication**

The current implementation does not take Authenticaition in to account. The real, production ready service might consider some authentication


