#!/usr/bin/env node

/**
 * Simple MCP Calculator Server Demo
 * 
 * This is a demonstration MCP server that provides basic mathematical operations.
 * It shows how to implement trusted operations that don't require user confirmation.
 */

const readline = require('readline');

class MCPCalculatorServer {
    constructor() {
        this.tools = [
            {
                name: "calculate",
                description: "Perform basic mathematical calculations",
                inputSchema: {
                    type: "object",
                    properties: {
                        expression: {
                            type: "string",
                            description: "Mathematical expression to evaluate (e.g., '2 + 3 * 4')"
                        }
                    },
                    required: ["expression"]
                }
            },
            {
                name: "convert_units",
                description: "Convert between different units",
                inputSchema: {
                    type: "object",
                    properties: {
                        value: {
                            type: "number",
                            description: "Numeric value to convert"
                        },
                        from_unit: {
                            type: "string",
                            description: "Source unit (e.g., 'celsius', 'fahrenheit', 'km', 'miles')"
                        },
                        to_unit: {
                            type: "string", 
                            description: "Target unit to convert to"
                        }
                    },
                    required: ["value", "from_unit", "to_unit"]
                }
            },
            {
                name: "generate_sequence",
                description: "Generate mathematical sequences",
                inputSchema: {
                    type: "object",
                    properties: {
                        type: {
                            type: "string",
                            enum: ["fibonacci", "prime", "square", "arithmetic"],
                            description: "Type of sequence to generate"
                        },
                        count: {
                            type: "number",
                            description: "Number of elements to generate",
                            minimum: 1,
                            maximum: 100
                        }
                    },
                    required: ["type", "count"]
                }
            }
        ];
    }

    handleRequest(request) {
        const method = request.method;
        const params = request.params || {};

        if (method === "tools/list") {
            return { tools: this.tools };
        } else if (method === "tools/call") {
            const toolName = params.name;
            const arguments_ = params.arguments || {};
            return this.callTool(toolName, arguments_);
        } else {
            return {
                error: {
                    code: -32601,
                    message: `Method not found: ${method}`
                }
            };
        }
    }

    callTool(toolName, arguments_) {
        try {
            switch (toolName) {
                case "calculate":
                    return this.calculate(arguments_.expression);
                case "convert_units":
                    return this.convertUnits(arguments_.value, arguments_.from_unit, arguments_.to_unit);
                case "generate_sequence":
                    return this.generateSequence(arguments_.type, arguments_.count);
                default:
                    return {
                        error: {
                            code: -32602,
                            message: `Unknown tool: ${toolName}`
                        }
                    };
            }
        } catch (error) {
            return {
                error: {
                    code: -32603,
                    message: `Tool execution failed: ${error.message}`
                }
            };
        }
    }

    calculate(expression) {
        if (!expression) {
            return {
                error: {
                    code: -32602,
                    message: "Expression is required"
                }
            };
        }

        try {
            // Basic safety check - only allow safe mathematical operations
            const safeExpression = expression.replace(/[^0-9+\-*/().\s]/g, '');
            
            if (safeExpression !== expression) {
                return {
                    error: {
                        code: -32603,
                        message: "Expression contains unsafe characters"
                    }
                };
            }

            // Evaluate the expression safely
            const result = Function(`"use strict"; return (${safeExpression})`)();
            
            return {
                content: [
                    {
                        type: "text",
                        text: `🔢 Calculation Result:\n\nExpression: ${expression}\nResult: ${result}`
                    }
                ]
            };
        } catch (error) {
            return {
                error: {
                    code: -32603,
                    message: `Invalid expression: ${error.message}`
                }
            };
        }
    }

    convertUnits(value, fromUnit, toUnit) {
        if (value === undefined || !fromUnit || !toUnit) {
            return {
                error: {
                    code: -32602,
                    message: "Value, from_unit, and to_unit are required"
                }
            };
        }

        const conversions = {
            // Temperature conversions
            celsius_fahrenheit: (c) => c * 9/5 + 32,
            fahrenheit_celsius: (f) => (f - 32) * 5/9,
            celsius_kelvin: (c) => c + 273.15,
            kelvin_celsius: (k) => k - 273.15,
            
            // Distance conversions  
            km_miles: (km) => km * 0.621371,
            miles_km: (mi) => mi * 1.60934,
            m_feet: (m) => m * 3.28084,
            feet_m: (ft) => ft * 0.3048,
            
            // Weight conversions
            kg_pounds: (kg) => kg * 2.20462,
            pounds_kg: (lb) => lb * 0.453592
        };

        const conversionKey = `${fromUnit.toLowerCase()}_${toUnit.toLowerCase()}`;
        const conversionFn = conversions[conversionKey];

        if (!conversionFn) {
            return {
                error: {
                    code: -32603,
                    message: `Conversion from ${fromUnit} to ${toUnit} not supported`
                }
            };
        }

        try {
            const result = conversionFn(value);
            
            return {
                content: [
                    {
                        type: "text",
                        text: `🔄 Unit Conversion:\n\n${value} ${fromUnit} = ${result.toFixed(4)} ${toUnit}`
                    }
                ]
            };
        } catch (error) {
            return {
                error: {
                    code: -32603,
                    message: `Conversion failed: ${error.message}`
                }
            };
        }
    }

    generateSequence(type, count) {
        if (!type || !count) {
            return {
                error: {
                    code: -32602,
                    message: "Type and count are required"
                }
            };
        }

        if (count < 1 || count > 100) {
            return {
                error: {
                    code: -32602,
                    message: "Count must be between 1 and 100"
                }
            };
        }

        try {
            let sequence = [];
            
            switch (type) {
                case "fibonacci":
                    sequence = this.generateFibonacci(count);
                    break;
                case "prime":
                    sequence = this.generatePrimes(count);
                    break;
                case "square":
                    sequence = Array.from({length: count}, (_, i) => (i + 1) ** 2);
                    break;
                case "arithmetic":
                    sequence = Array.from({length: count}, (_, i) => i + 1);
                    break;
                default:
                    return {
                        error: {
                            code: -32602,
                            message: `Unknown sequence type: ${type}`
                        }
                    };
            }
            
            return {
                content: [
                    {
                        type: "text",
                        text: `📊 ${type.charAt(0).toUpperCase() + type.slice(1)} Sequence (${count} elements):\n\n${sequence.join(', ')}`
                    }
                ]
            };
        } catch (error) {
            return {
                error: {
                    code: -32603,
                    message: `Sequence generation failed: ${error.message}`
                }
            };
        }
    }

    generateFibonacci(count) {
        const sequence = [0, 1];
        for (let i = 2; i < count; i++) {
            sequence[i] = sequence[i-1] + sequence[i-2];
        }
        return sequence.slice(0, count);
    }

    generatePrimes(count) {
        const primes = [];
        let num = 2;
        
        while (primes.length < count) {
            if (this.isPrime(num)) {
                primes.push(num);
            }
            num++;
        }
        
        return primes;
    }

    isPrime(num) {
        if (num < 2) return false;
        for (let i = 2; i <= Math.sqrt(num); i++) {
            if (num % i === 0) return false;
        }
        return true;
    }
}

function main() {
    const server = new MCPCalculatorServer();
    const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout
    });

    console.error('Calculator MCP Server started');

    rl.on('line', (line) => {
        try {
            const request = JSON.parse(line.trim());
            const response = server.handleRequest(request);
            console.log(JSON.stringify(response));
        } catch (error) {
            const errorResponse = {
                error: {
                    code: -32700,
                    message: `Parse error: Invalid JSON - ${error.message}`
                }
            };
            console.log(JSON.stringify(errorResponse));
        }
    });

    rl.on('close', () => {
        console.error('Calculator MCP Server shutting down');
        process.exit(0);
    });
}

if (require.main === module) {
    main();
}