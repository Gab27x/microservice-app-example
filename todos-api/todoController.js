'use strict';
const cache = require('memory-cache');
const {Annotation, 
    jsonEncoder: {JSON_V2}} = require('zipkin');
const CACHE_TTL_SECONDS = parseInt(process.env.CACHE_TTL_SECONDS || '60', 10);

const OPERATION_CREATE = 'CREATE',
      OPERATION_DELETE = 'DELETE';

class TodoController {
    constructor({tracer, redisClient, logChannel}) {
        this._tracer = tracer;
        this._redisClient = redisClient;
        this._logChannel = logChannel;
    }

    // TODO: these methods are not concurrent-safe
    list (req, res) {
        this._getTodoDataAsync(req.user.username, (err, data, cacheHit) => {
            if (err) {
                res.status(500).json({ message: 'cache error', error: '' + err });
                return;
            }
            try {
                res.set('X-Cache', cacheHit ? 'HIT' : 'MISS');
            } catch (e) {}
            res.json(data.items)
        })
    }

    create (req, res) {
        // TODO: must be transactional and protected for concurrent access, but
        // the purpose of the whole example app it's enough
        const data = this._getTodoData(req.user.username)
        const todo = {
            content: req.body.content,
            id: data.lastInsertedID
        }
        data.items[data.lastInsertedID] = todo

        data.lastInsertedID++
        this._setTodoData(req.user.username, data)

        // Cache-aside: invalidar entrada en caché para que se regenere en próxima lectura
        this._invalidateCache(req.user.username)

        this._logOperation(OPERATION_CREATE, req.user.username, todo.id)

        res.json(todo)
    }

    delete (req, res) {
        const data = this._getTodoData(req.user.username)
        const id = req.params.taskId
        delete data.items[id]
        this._setTodoData(req.user.username, data)

        // Cache-aside: invalidar caché tras mutación
        this._invalidateCache(req.user.username)

        this._logOperation(OPERATION_DELETE, req.user.username, id)

        res.status(204)
        res.send()
    }

    _logOperation (opName, username, todoId) {
        this._tracer.scoped(() => {
            const traceId = this._tracer.id;
            this._redisClient.publish(this._logChannel, JSON.stringify({
                zipkinSpan: traceId,
                opName: opName,
                username: username,
                todoId: todoId,
            }))
        })
    }

    _getTodoData (userID) {
        var data = cache.get(userID)
        if (data == null) {
            data = {
                items: {
                    '1': {
                        id: 1,
                        content: "Create new todo",
                    },
                    '2': {
                        id: 2,
                        content: "Update me",
                    },
                    '3': {
                        id: 3,
                        content: "Delete example ones",
                    }
                },
                lastInsertedID: 3
            }

            this._setTodoData(userID, data)
        }
        return data
    }

    _setTodoData (userID, data) {
        cache.put(userID, data)
    }

    _getCacheKey (userID) {
        return `todos:${userID}`
    }

    // Obtiene datos desde Redis si existen; si no, los carga del "almacén" en memoria y
    // los almacena en Redis con TTL. Callback: (err, data, cacheHit:boolean)
    _getTodoDataAsync (userID, cb) {
        const key = this._getCacheKey(userID)
        this._redisClient.get(key, (err, reply) => {
            if (err) return cb(err)
            if (reply) {
                try {
                    const parsed = JSON.parse(reply)
                    return cb(null, parsed, true)
                } catch (e) {
                    // si no se puede parsear, tratamos como miss
                }
            }
            const data = this._getTodoData(userID)
            try {
                this._redisClient.setex(key, CACHE_TTL_SECONDS, JSON.stringify(data), (e2) => {
                    // si falla el setex, continuamos sirviendo desde el origen
                    return cb(null, data, false)
                })
            } catch (e3) {
                return cb(null, data, false)
            }
        })
    }

    _invalidateCache (userID) {
        const key = this._getCacheKey(userID)
        try {
            this._redisClient.del(key, function(){})
        } catch (e) {}
    }
}

module.exports = TodoController